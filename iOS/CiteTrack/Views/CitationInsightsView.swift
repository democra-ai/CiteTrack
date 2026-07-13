import SwiftUI

// MARK: - Citation Insights View
/// Aggregates citation context across selected papers for a scholar.
/// Flow: Select Scholar → Filter/Select Publications → Analyze → Drill into each publication
/// Results are incremental: each Analyze adds to saved results, never replaces them.
struct CitationInsightsView: View {
    @StateObject private var auth = GoogleAuthService.shared
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var contextService = CitationContextService.shared
    @StateObject private var citationManager = CitationManager.shared

    @AppStorage("ConfirmedMyScholarId") private var confirmedMyScholarId: String?

    @State private var showSignIn = false
    @State private var selectedScholarId: String?
    @State private var publicationResults: [CitationContextService.PublicationCitationResults] = []
    @State private var hasFetched = false

    // Publication selection
    @State private var publicationsWithAuthors: [CitationContextService.PublicationWithAuthors] = []
    @State private var selectedPubIds: Set<String> = []
    @State private var showPublicationPicker = false
    @State private var isFetchingAuthors = false
    @State private var isRefiningRoles = false
    @State private var roleRefineTask: Task<Void, Never>? = nil
    @State private var loadError: String?
    @State private var hasAuthorInfo = false
    @State private var pickerRoleFilter: CitationContextService.AuthorRole? = nil
    @State private var showClearAllConfirm = false

    /// Localization shortcut — all keys are registered (en+zh) in LocalizationManager.
    private func L(_ key: String) -> String { LocalizationManager.shared.localized(key) }
    private func L(_ key: String, _ args: CVarArg...) -> String {
        String(format: LocalizationManager.shared.localized(key), arguments: args)
    }
    /// Localized author-role name (model enum's displayName is English-only).
    private func roleName(_ role: CitationContextService.AuthorRole) -> String {
        switch role {
        case .firstAuthor: return L("role_first")
        case .coFirstAuthor: return L("role_co_first")
        case .correspondingAuthor: return L("role_corresponding")
        case .middleAuthor: return L("role_middle")
        case .unknown: return L("role_unknown")
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if auth.isSignedIn {
                    insightsBody
                } else {
                    signInGate
                }
            }
            .navigationTitle(L("insights_title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let user = auth.currentUser {
                        SignedInUserBadge(user: user) { auth.signOut() }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onDisappear { roleRefineTask?.cancel() }
        .sheet(isPresented: $showSignIn) {
            GoogleSignInView { onSignedIn() }
        }
        .sheet(isPresented: $showPublicationPicker) {
            publicationPickerSheet
        }
        .onAppear {
            guard auth.isSignedIn else { return }
            initializeAndLoadCached()
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { onSignedIn() }
        }
        .task(id: selectedScholarId) {
            guard let sid = selectedScholarId else { return }
            guard publicationsWithAuthors.isEmpty, !isFetchingAuthors else { return }
            loadOrFetchPublications(sid)
        }
    }

    // MARK: - Helpers

    private var sortedScholars: [Scholar] {
        let scholars = dataManager.scholars
        guard let myId = confirmedMyScholarId else { return scholars }
        var me: Scholar?
        var others: [Scholar] = []
        for s in scholars {
            if s.id == myId { me = s } else { others.append(s) }
        }
        if let me = me { return [me] + others }
        return scholars
    }

    private var selectedScholarName: String {
        dataManager.scholars.first(where: { $0.id == selectedScholarId })?.name ?? ""
    }

    /// Currently-selected Scholar object (nil if none picked).
    private var currentScholar: Scholar? {
        dataManager.scholars.first(where: { $0.id == selectedScholarId })
    }

    /// Publications to feed into the analysis API (drawn from picker state with author info).
    private var publicationsForAnalysis: [ScholarPublication] {
        publicationsWithAuthors.map { pwa in
            ScholarPublication(
                title: pwa.title,
                clusterId: pwa.id,
                citationCount: pwa.citationCount,
                year: pwa.year,
                authors: pwa.authors
            )
        }
    }

    /// Flatten and dedupe citing papers from analyzed publication results so we can ship
    /// them to the backend analysis worker.
    private var citingPapersForAnalysis: [CitingPaper] {
        guard let scholarId = selectedScholarId else { return [] }
        var byId: [String: CitingPaper] = [:]
        for pub in publicationResults {
            for cp in pub.citingPapers {
                if byId[cp.id] != nil { continue }
                byId[cp.id] = CitingPaper(
                    id: cp.id,
                    title: cp.citingPaperTitle,
                    authors: cp.citingAuthors,
                    year: cp.citingYear,
                    venue: nil,
                    citationCount: nil,
                    abstract: cp.contexts.isEmpty ? nil : cp.contexts.joined(separator: " "),
                    scholarUrl: nil,
                    pdfUrl: nil,
                    citedScholarId: scholarId
                )
            }
        }
        return Array(byId.values)
    }

    /// Whether at least one analyzed publication has citing papers to analyze per-paper.
    private var hasAnalyzablePapers: Bool {
        publicationResults.contains { $0.fetchStatus == .success && !$0.citingPapers.isEmpty }
    }

    /// IDs of publications considered "done": only successfully fetched ones, or
    /// papers definitively not indexed on Semantic Scholar. Rate-limited and error
    /// results are transient, so they stay OUT of this set and remain retryable —
    /// tapping "Analyze" again will re-fetch them.
    private var alreadyAnalyzedIds: Set<String> {
        Set(publicationResults
            .filter { $0.fetchStatus == .success || $0.fetchStatus == .notFoundOnSS }
            .map { $0.id })
    }

    /// Number of selected publications not yet analyzed
    private var newToAnalyzeCount: Int {
        selectedPubIds.subtracting(alreadyAnalyzedIds).count
    }

    // MARK: - Initialization

    private func initializeAndLoadCached() {
        if selectedScholarId == nil {
            selectedScholarId = confirmedMyScholarId ?? dataManager.scholars.first?.id
        }
        guard let scholarId = selectedScholarId else { return }

        // Load persisted analysis results
        if let cached = contextService.loadPublicationResults(forScholar: scholarId) {
            publicationResults = cached.results
            hasFetched = !cached.results.isEmpty
        }

        loadOrFetchPublications(scholarId)
    }

    private func loadOrFetchPublications(_ scholarId: String) {
        // Collect data from all available sources and merge for best author coverage
        let ssPubs = contextService.loadPublicationAuthors(forScholar: scholarId)
        let gsPubs = UnifiedCacheManager.shared.getPublications(
            scholarId: scholarId, sortBy: "total", startIndex: 0, limit: 1000
        )

        // Build GS author lookup
        var gsAuthorsById: [String: [String]] = [:]
        if let gsPubs = gsPubs {
            for pub in gsPubs where !pub.authors.isEmpty {
                gsAuthorsById[pub.id] = pub.authors
            }
        }

        // Merge: use SS data as base, supplement empty authors with GS data
        if let ssPubs = ssPubs, !ssPubs.isEmpty {
            let merged = ssPubs.map { pub -> CitationContextService.PublicationWithAuthors in
                if pub.authors.isEmpty, let gsAuthors = gsAuthorsById[pub.id], !gsAuthors.isEmpty {
                    return CitationContextService.PublicationWithAuthors(
                        id: pub.id, title: pub.title, year: pub.year,
                        citationCount: pub.citationCount, authors: gsAuthors
                    )
                }
                return pub
            }
            publicationsWithAuthors = merged
            hasAuthorInfo = merged.contains { !$0.authors.isEmpty }
            if selectedPubIds.isEmpty {
                selectedPubIds = Set(merged.map { $0.id })
            }

            // If still too many missing, force a fresh fetch from GS.
            // (OpenAlex author-role refinement is temporarily disabled — it caused
            // app-wide stutter. detectRole's conservative heuristic still fixes the
            // first-author/corresponding bug with no network work.)
            let withAuthors = merged.filter { !$0.authors.isEmpty }.count
            if withAuthors < merged.count / 2 {
                fetchFreshAuthorsFromGS(scholarId)
            }
            return
        }

        // No SS data — use GS data
        if let gsPubs = gsPubs, !gsPubs.isEmpty {
            let mapped = gsPubs.map { pub in
                CitationContextService.PublicationWithAuthors(
                    id: pub.id, title: pub.title, year: pub.year,
                    citationCount: pub.citationCount, authors: pub.authors
                )
            }
            publicationsWithAuthors = mapped
            hasAuthorInfo = gsPubs.contains { !$0.authors.isEmpty }
            selectedPubIds = Set(mapped.map { $0.id })

            // If many authors missing, force a fresh fetch. (OpenAlex refinement disabled.)
            let withAuthors = mapped.filter { !$0.authors.isEmpty }.count
            if withAuthors < mapped.count / 2 {
                fetchFreshAuthorsFromGS(scholarId)
            }
            return
        }

        // Last resort: fetch from network
        loadPublications(forScholar: scholarId)
    }

    /// Force a fresh fetch of the scholar's profile page from GS to get correct author lists.
    /// This makes one GS request and updates the UI + cache with fresh author data.
    private func fetchFreshAuthorsFromGS(_ scholarId: String) {
        guard !isFetchingAuthors else { return }
        isFetchingAuthors = true
        NSLog("📖 [Insights] Fetching fresh author data from GS for %@", scholarId)

        Task {
            let freshPubs: [ScholarPublication] = await withCheckedContinuation { continuation in
                CitationFetchService.shared.fetchScholarPublications(
                    for: scholarId, sortBy: nil, startIndex: 0, forceRefresh: true
                ) { result in
                    switch result {
                    case .success(let pubs): continuation.resume(returning: pubs)
                    case .failure: continuation.resume(returning: [])
                    }
                }
            }

            guard !freshPubs.isEmpty else {
                isFetchingAuthors = false
                return
            }

            let mapped = freshPubs.map { pub in
                CitationContextService.PublicationWithAuthors(
                    id: pub.id, title: pub.title, year: pub.year,
                    citationCount: pub.citationCount, authors: pub.authors
                )
            }

            let withAuthors = mapped.filter { !$0.authors.isEmpty }.count
            NSLog("📖 [Insights] Fresh GS data: %d/%d have authors", withAuthors, mapped.count)

            await MainActor.run {
                let oldSelection = selectedPubIds
                publicationsWithAuthors = mapped
                hasAuthorInfo = withAuthors > 0
                if oldSelection.isEmpty {
                    selectedPubIds = Set(mapped.map { $0.id })
                }
                isFetchingAuthors = false

                // Save to PubAuthors cache for next session
                contextService.savePublicationAuthors(mapped, forScholar: scholarId)
            }
        }
    }

    /// Refine author roles using OpenAlex (authoritative complete author lists +
    /// author_position / is_corresponding). Fixes the case where a TRUNCATED
    /// Semantic Scholar / Google Scholar list made a middle author look "last" and
    /// get mis-labeled corresponding. Runs in the background; results are cached.
    private func refineRolesViaOpenAlex(scholarId: String, scholarName: String) {
        guard !scholarName.isEmpty, !isRefiningRoles else { return }
        let pending = publicationsWithAuthors.filter { !$0.authorListComplete }
        guard !pending.isEmpty else { return }
        isRefiningRoles = true
        roleRefineTask = Task {
            defer { Task { @MainActor in isRefiningRoles = false } }
            // Resolve in the background and COLLECT results, then apply them to the UI
            // ONCE at the end. The previous version reassigned publicationsWithAuthors
            // after every single network call — dozens of full list re-renders that made
            // the whole app feel frozen. Capped + cancellable when leaving the tab.
            var refinedById: [String: CitationContextService.PublicationWithAuthors] = [:]
            for pub in pending.prefix(40) {
                if Task.isCancelled { break }
                guard let resolved = await OpenAlexEnrichmentClient.shared.resolveOwnAuthorship(
                    title: pub.title, year: pub.year, scholarName: scholarName
                ) else { continue }
                // Only trust the OpenAlex match when the scholar actually appears in it.
                // A match where the scholar isn't found is almost always a wrong-paper
                // match (similar title) — replacing the author list there would show the
                // wrong authors. Keep the original list in that case.
                guard resolved.matchedIndex != nil, !resolved.authorNames.isEmpty else { continue }
                refinedById[pub.id] = CitationContextService.PublicationWithAuthors(
                    id: pub.id,
                    title: pub.title,
                    year: pub.year,
                    citationCount: pub.citationCount,
                    authors: resolved.authorNames,
                    authorListComplete: true,
                    correspondingByOpenAlex: resolved.isCorresponding
                )
            }
            guard !refinedById.isEmpty else { return }
            await MainActor.run {
                publicationsWithAuthors = publicationsWithAuthors.map { refinedById[$0.id] ?? $0 }
                hasAuthorInfo = publicationsWithAuthors.contains { !$0.authors.isEmpty }
                contextService.savePublicationAuthors(publicationsWithAuthors, forScholar: scholarId)
            }
        }
    }

    private func onSignedIn() {
        initializeAndLoadCached()
    }

    // MARK: - Sign-In Gate

    private var signInGate: some View {
        VStack(spacing: 36) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(spacing: 8) {
                Text(L("insights_title"))
                    .font(.title2).fontWeight(.bold)
                Text(L("insights_signin_subtitle"))
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Text(L("insights_signin_desc"))
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            SignInButtons(onGoogle: { showSignIn = true })
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Main Content

    private var insightsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                // 1. Scholar picker
                GlassCard { scholarPicker }

                // 2. Publication selection + Analyze
                GlassCard { publicationSelectionRow }

                // 3. Progress (when running)
                if contextService.batchProgress.isRunning {
                    GlassCard { progressView }
                }

                // 4. Results — summary + AI analysis + per-publication drill-down
                if hasFetched && !contextService.batchProgress.isRunning {
                    GlassCard { summaryCard }

                    if let scholar = currentScholar, hasAnalyzablePapers {
                        PerPaperAnalysisListCard(
                            scholar: scholar,
                            pubResults: publicationResults,
                            publicationsForAnalysis: publicationsForAnalysis
                        )
                    }

                    publicationsCard

                    if !contextService.batchProgress.errors.isEmpty {
                        issuesCard
                    }
                }

                // 5. Feedback prompt — always available so users can tell us how
                //    the impact-analysis feature is working for them.
                GlassCard { InsightsFeedbackPrompt() }
            }
            .padding(GlassMetrics.screenPadding)
            .iPadReadableWidth()
        }
        .liquidGlassCanvas()
        .confirmationDialog(
            LocalizationManager.shared.localized("insights_clear_all_confirm", fallback: "清空所有已分析的论文？海优评分也会一并删除。"),
            isPresented: $showClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button(LocalizationManager.shared.localized("insights_clear_all", fallback: "清空"), role: .destructive) {
                clearAllPublicationResults()
            }
            Button(LocalizationManager.shared.localized("cancel", fallback: "取消"), role: .cancel) {}
        }
    }

    // Your Publications — a glass card with per-row navigation + an explicit delete
    // button (swipe-to-delete is List-only; this view is now a ScrollView).
    private var publicationsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("insights_your_publications", publicationResults.count))
                        .font(.footnote.weight(.semibold)).textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !publicationResults.isEmpty {
                        Button(role: .destructive) {
                            showClearAllConfirm = true
                        } label: {
                            Text(L("insights_clear_all")).font(.caption)
                        }
                    }
                }

                if publicationResults.isEmpty {
                    emptyResultsRow
                } else {
                    ForEach(Array(publicationResults.enumerated()), id: \.element.id) { idx, pubResult in
                        HStack(spacing: 10) {
                            NavigationLink {
                                PublicationCitationDetailView(
                                    publicationResult: pubResult,
                                    scholarName: selectedScholarName
                                )
                            } label: {
                                HStack(spacing: 6) {
                                    publicationResultRow(pubResult)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                deletePublicationResult(pubResult)
                            } label: {
                                Image(systemName: "trash").font(.subheadline).foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        if idx < publicationResults.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    private var issuesCard: some View {
        GlassSection(title: L("insights_issues")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(contextService.batchProgress.errors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Scholar Picker

    private var scholarPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("insights_select_scholar"))
                .font(.caption).foregroundColor(.secondary).textCase(.uppercase)

            if dataManager.scholars.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus").foregroundColor(.secondary)
                    Text(L("insights_add_scholar_first"))
                        .font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sortedScholars) { scholar in
                            scholarChip(scholar)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scholarChip(_ scholar: Scholar) -> some View {
        let isSelected = selectedScholarId == scholar.id
        let isMe = scholar.id == confirmedMyScholarId
        return Button {
            selectedScholarId = scholar.id
            loadCachedForScholar(scholar.id)
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    if isMe {
                        Image(systemName: "person.fill").font(.caption2)
                    }
                    Text(scholar.displayName)
                        .font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                }
                if let citations = scholar.citations {
                    Text(L("insights_citations_suffix", citations))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(.systemGray6).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.06),
                                  lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
    }

    private func loadCachedForScholar(_ scholarId: String) {
        publicationsWithAuthors = []
        selectedPubIds = []
        hasAuthorInfo = false
        pickerRoleFilter = nil

        if let cached = contextService.loadPublicationResults(forScholar: scholarId) {
            publicationResults = cached.results
            hasFetched = !cached.results.isEmpty
        } else {
            publicationResults = []
            hasFetched = false
        }

        loadOrFetchPublications(scholarId)
    }

    // MARK: - Publication Selection + Analyze

    private var publicationSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("insights_select_publications"))
                .font(.caption).foregroundColor(.secondary).textCase(.uppercase)

            if publicationsWithAuthors.isEmpty {
                if isFetchingAuthors {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text(L("insights_loading_pubs"))
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if let error = loadError {
                    VStack(spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                        Button(L("insights_retry")) {
                            if let sid = selectedScholarId {
                                loadPublications(forScholar: sid)
                            }
                        }
                        .font(.subheadline)
                    }
                } else if selectedScholarId != nil {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text(L("insights_preparing"))
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(L("insights_select_scholar_hint"))
                        .font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                // Role summary chips
                let grouped = groupedByRole
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(grouped.keys.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { role in
                            let pubs = grouped[role] ?? []
                            let selectedInRole = pubs.filter { selectedPubIds.contains($0.id) }.count
                            GlassChip(
                                text: "\(selectedInRole)/\(pubs.count)",
                                systemImage: role.icon,
                                tint: role.color,
                                prominent: selectedInRole > 0
                            )
                        }
                    }
                }

                HStack {
                    Text(L("insights_selected_count", selectedPubIds.count, publicationsWithAuthors.count))
                        .font(.subheadline)
                    Spacer()
                }

                // Two buttons: Choose + Analyze
                HStack(spacing: 12) {
                    Button {
                        showPublicationPicker = true
                    } label: {
                        Label(L("insights_choose"), systemImage: "checklist")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .secondaryGlassButton()

                    Button {
                        startBatchFetch()
                    } label: {
                        let count = newToAnalyzeCount
                        Label(
                            count > 0 ? L("insights_analyze_n", count) : L("insights_all_analyzed"),
                            systemImage: "magnifyingglass"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                    }
                    .primaryGlassButton()
                    .disabled(newToAnalyzeCount == 0 || contextService.batchProgress.isRunning)
                }

                // Show how many already analyzed
                if !publicationResults.isEmpty {
                    Text(L("insights_n_analyzed", publicationResults.count))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var groupedByRole: [CitationContextService.AuthorRole: [CitationContextService.PublicationWithAuthors]] {
        let name = selectedScholarName
        var groups: [CitationContextService.AuthorRole: [CitationContextService.PublicationWithAuthors]] = [:]
        for pub in publicationsWithAuthors {
            let role = pub.detectRole(scholarName: name)
            groups[role, default: []].append(pub)
        }
        return groups
    }

    // MARK: - Publication Picker Sheet

    private var pickerFilteredPubs: [CitationContextService.PublicationWithAuthors] {
        guard let filter = pickerRoleFilter else { return publicationsWithAuthors }
        let name = selectedScholarName
        return publicationsWithAuthors.filter { $0.detectRole(scholarName: name) == filter }
    }

    private var publicationPickerSheet: some View {
        let grouped = groupedByRole
        let allRoles: [CitationContextService.AuthorRole] = [.firstAuthor, .coFirstAuthor, .correspondingAuthor, .middleAuthor, .unknown]

        return NavigationView {
            List {
                Section {
                    if hasAuthorInfo {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                roleFilterChip(role: nil, label: L("insights_all"), count: publicationsWithAuthors.count,
                                               icon: "person.3", color: .accentColor)
                                ForEach(allRoles, id: \.self) { role in
                                    let count = grouped[role]?.count ?? 0
                                    if count > 0 {
                                        roleFilterChip(role: role, label: roleName(role), count: count,
                                                       icon: role.icon, color: role.color)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        let filteredIds = Set(pickerFilteredPubs.map(\.id))
                        if selectedPubIds.isSuperset(of: filteredIds) {
                            selectedPubIds.subtract(filteredIds)
                        } else {
                            selectedPubIds.formUnion(filteredIds)
                        }
                    } label: {
                        let filteredIds = Set(pickerFilteredPubs.map(\.id))
                        HStack {
                            Image(systemName: selectedPubIds.isSuperset(of: filteredIds) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.accentColor)
                            Text(selectedPubIds.isSuperset(of: filteredIds) ? L("insights_deselect_all") : L("insights_select_all"))
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(selectedPubIds.intersection(filteredIds).count)/\(filteredIds.count)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section(L("insights_publications_count", pickerFilteredPubs.count)) {
                    ForEach(pickerFilteredPubs) { pub in
                        let role = pub.detectRole(scholarName: selectedScholarName)
                        publicationRow(pub, role: role)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .liquidGlassCanvas()
            .navigationTitle(L("insights_select_publications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("insights_done")) { showPublicationPicker = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func roleFilterChip(role: CitationContextService.AuthorRole?, label: String,
                                count: Int, icon: String, color: Color) -> some View {
        let isActive = pickerRoleFilter == role
        return Button {
            pickerRoleFilter = role
        } label: {
            GlassChip(
                text: "\(label) \(count)",
                systemImage: icon,
                tint: isActive ? color : .secondary,
                prominent: isActive
            )
        }
        .buttonStyle(.plain)
    }

    private func publicationRow(_ pub: CitationContextService.PublicationWithAuthors, role: CitationContextService.AuthorRole) -> some View {
        let isAnalyzed = alreadyAnalyzedIds.contains(pub.id)
        return Button {
            if selectedPubIds.contains(pub.id) {
                selectedPubIds.remove(pub.id)
            } else {
                selectedPubIds.insert(pub.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedPubIds.contains(pub.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedPubIds.contains(pub.id) ? .accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pub.title)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(3)

                    if !pub.authors.isEmpty {
                        authorHighlightText(pub.authors, role: role)
                    }

                    HStack(spacing: 8) {
                        if let year = pub.year {
                            Text(verbatim: "\(year)").font(.caption2).foregroundColor(.secondary)
                        }
                        if let count = pub.citationCount, count > 0 {
                            Text(L("insights_cited_by", count))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        if hasAuthorInfo && role != .unknown {
                            Text(roleName(role))
                                .font(.caption2).fontWeight(.medium)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(role.color.opacity(0.15))
                                .foregroundColor(role.color)
                                .cornerRadius(3)
                        }
                        if isAnalyzed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2).foregroundColor(.green)
                        }
                    }
                }
            }
        }
    }

    private func authorHighlightText(_ authors: [String], role: CitationContextService.AuthorRole) -> some View {
        let name = selectedScholarName
        let display = Array(authors.prefix(8))
        // Build one flowing Text run so it wraps naturally (the old HStack stayed on
        // a single line and clipped long author lists). The scholar is highlighted
        // with a single consistent accent, not the per-role color.
        var line = Text("")
        for (idx, author) in display.enumerated() {
            let isMe = CitationContextService.PublicationWithAuthors.namesMatch(author, name)
            if idx > 0 { line = line + Text(", ").foregroundColor(.secondary) }
            line = line + Text(author)
                .fontWeight(isMe ? .semibold : .regular)
                .foregroundColor(isMe ? .accentColor : .secondary)
        }
        if authors.count > display.count {
            line = line + Text(" " + "et_al".localized).foregroundColor(.secondary)
        }
        return line.font(.caption).lineLimit(2)
    }

    // MARK: - Progress View

    private var progressView: some View {
        let progress = contextService.batchProgress
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text(L("insights_analyzing"))
                    .font(.subheadline).fontWeight(.medium)
                Spacer()
                Text("\(progress.currentPaperIndex)/\(progress.totalPapers)")
                    .font(.caption).foregroundColor(.secondary)
            }
            ProgressView(value: progress.fraction).tint(.accentColor)
            Text(progress.currentPaperTitle)
                .font(.caption).foregroundColor(.secondary).lineLimit(1)
            if progress.totalContextsFound > 0 {
                Text(L("insights_contexts_found", progress.totalContextsFound))
                    .font(.caption).foregroundColor(.green)
            }
            if progress.successCount > 0 || progress.notFoundCount > 0 {
                HStack(spacing: 12) {
                    if progress.successCount > 0 {
                        Label(L("insights_done_count", progress.successCount), systemImage: "checkmark.circle")
                            .font(.caption2).foregroundColor(.green)
                    }
                    if progress.notFoundCount > 0 {
                        Label(L("insights_notfound_count", progress.notFoundCount), systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        let totalCiting = publicationResults.reduce(0) { $0 + $1.citingPapers.count }
        let totalContexts = publicationResults.reduce(0) { $0 + $1.totalContexts }

        return HStack(spacing: 20) {
            statCell(value: "\(publicationResults.count)", label: L("insights_papers_analyzed"),
                     icon: "doc.text.magnifyingglass", color: .blue)
            Divider().frame(height: 40)
            statCell(value: "\(totalCiting)", label: L("insights_citing_papers"),
                     icon: "doc.on.doc", color: .purple)
            Divider().frame(height: 40)
            statCell(value: "\(totalContexts)", label: L("insights_contexts"),
                     icon: "text.quote", color: .green)
        }
        .padding(.vertical, 8)
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        GlassStatCell(value: value, label: label, systemImage: icon, tint: color)
    }

    // MARK: - Publication Result Row

    private func publicationResultRow(_ pubResult: CitationContextService.PublicationCitationResults) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pubResult.publicationTitle)
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let year = pubResult.publicationYear {
                    Text(verbatim: "\(year)")
                        .font(.caption).foregroundColor(.secondary)
                }
                if pubResult.fetchStatus == .notFoundOnSS {
                    Label(L("insights_not_on_ss"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange)
                } else if pubResult.fetchStatus == .rateLimited {
                    Label(L("insights_rate_limited"), systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundColor(.orange)
                } else if pubResult.fetchStatus == .error {
                    Label(L("insights_error"), systemImage: "xmark.circle")
                        .font(.caption).foregroundColor(.red)
                } else {
                    Label(L("insights_n_citing", pubResult.citingPapers.count), systemImage: "doc.on.doc")
                        .font(.caption).foregroundColor(.purple)
                    if pubResult.totalContexts > 0 {
                        Label(L("insights_n_quotes", pubResult.totalContexts), systemImage: "text.quote")
                            .font(.caption).foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptyResultsRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass").font(.title2).foregroundColor(.secondary)
            Text(L("insights_no_data")).font(.subheadline).foregroundColor(.secondary)
            Text(L("insights_no_data_desc"))
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func loadPublications(forScholar overrideId: String? = nil) {
        let scholarId = overrideId ?? selectedScholarId
        guard let scholarId = scholarId else { return }
        guard !isFetchingAuthors else { return }
        isFetchingAuthors = true
        loadError = nil

        Task {
            var pubs: [PublicationInfo] = []

            let cachedPubs = await MainActor.run {
                UnifiedCacheManager.shared.getPublications(
                    scholarId: scholarId, sortBy: "total", startIndex: 0, limit: 1000
                )
            }
            if let cachedPubs = cachedPubs, !cachedPubs.isEmpty {
                pubs = cachedPubs.map { pub in
                    PublicationInfo(
                        id: pub.id, title: pub.title,
                        clusterId: pub.clusterId,
                        citationCount: pub.citationCount, year: pub.year
                    )
                }
            }

            if pubs.isEmpty {
                pubs = citationManager.scholarPublications[scholarId] ?? []
            }

            if pubs.isEmpty {
                pubs = await fetchPublicationsDirectly(for: scholarId)
            }

            if pubs.isEmpty {
                loadError = "No publications found. Try again later."
                isFetchingAuthors = false
                return
            }

            let gsAuthors: [[String]]
            if let cachedPubs = cachedPubs {
                gsAuthors = cachedPubs.map { $0.authors }
            } else {
                gsAuthors = Array(repeating: [], count: pubs.count)
            }
            publicationsWithAuthors = pubs.enumerated().map { idx, pub in
                let authors = idx < gsAuthors.count ? gsAuthors[idx] : []
                return CitationContextService.PublicationWithAuthors(
                    id: pub.id, title: pub.title, year: pub.year,
                    citationCount: pub.citationCount, authors: authors
                )
            }
            selectedPubIds = Set(publicationsWithAuthors.map { $0.id })
            hasAuthorInfo = publicationsWithAuthors.contains { !$0.authors.isEmpty }
            isFetchingAuthors = false
        }
    }

    private func fetchPublicationsDirectly(for scholarId: String) async -> [PublicationInfo] {
        await withCheckedContinuation { continuation in
            CitationFetchService.shared.fetchScholarPublications(
                for: scholarId, sortBy: nil, startIndex: 0, forceRefresh: false
            ) { result in
                switch result {
                case .success(let publications):
                    let pubInfos = publications.map { pub in
                        PublicationInfo(
                            id: pub.id,
                            title: pub.title,
                            clusterId: pub.clusterId,
                            citationCount: pub.citationCount,
                            year: pub.year
                        )
                    }
                    continuation.resume(returning: pubInfos)
                case .failure:
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Incremental analyze: only fetch publications not already analyzed, merge with existing results
    private func startBatchFetch() {
        guard let scholarId = selectedScholarId else { return }

        // Determine which publications still need analysis
        let idsToAnalyze = selectedPubIds.subtracting(alreadyAnalyzedIds)
        guard !idsToAnalyze.isEmpty else { return }

        Task {
            var pubs: [PublicationInfo] = []

            let cachedPubs = await MainActor.run {
                UnifiedCacheManager.shared.getPublications(
                    scholarId: scholarId, sortBy: "total", startIndex: 0, limit: 1000
                )
            }
            if let cachedPubs = cachedPubs, !cachedPubs.isEmpty {
                pubs = cachedPubs.map { pub in
                    PublicationInfo(
                        id: pub.id, title: pub.title,
                        clusterId: pub.clusterId,
                        citationCount: pub.citationCount, year: pub.year
                    )
                }
            }

            if pubs.isEmpty {
                pubs = citationManager.scholarPublications[scholarId] ?? []
            }
            if pubs.isEmpty {
                pubs = await fetchPublicationsDirectly(for: scholarId)
            }

            let name = selectedScholarName
            let newResults = await contextService.fetchAllContextsForScholar(
                scholarId: scholarId, scholarName: name, publications: pubs,
                selectedIds: idsToAnalyze
            )

            // Merge: replace any existing entry for the same publication (so a prior
            // rate-limited/error result gets overwritten by a fresh successful one),
            // and append newly-analyzed publications.
            var merged = publicationResults
            for result in newResults {
                if let idx = merged.firstIndex(where: { $0.id == result.id }) {
                    merged[idx] = result
                } else {
                    merged.append(result)
                }
            }

            publicationResults = merged
            hasFetched = true

            // Persist the merged results
            contextService.savePublicationResults(merged, forScholar: scholarId)
        }
    }

    // MARK: - Delete analyzed publications

    /// Delete a single analyzed publication. It leaves `alreadyAnalyzedIds`,
    /// so it can be selected and re-analyzed afterwards.
    private func deletePublicationResult(_ pubResult: CitationContextService.PublicationCitationResults) {
        publicationResults.removeAll { $0.id == pubResult.id }
        persistResultsAfterDeletion()
    }

    private func deletePublicationResults(at offsets: IndexSet) {
        publicationResults.remove(atOffsets: offsets)
        persistResultsAfterDeletion()
    }

    private func clearAllPublicationResults() {
        publicationResults.removeAll()
        persistResultsAfterDeletion()
    }

    private func persistResultsAfterDeletion() {
        guard let scholarId = selectedScholarId else { return }
        contextService.savePublicationResults(publicationResults, forScholar: scholarId)
        if publicationResults.isEmpty {
            hasFetched = false
        }
    }
}

// MARK: - Publication Citation Detail View

struct PublicationCitationDetailView: View {
    let publicationResult: CitationContextService.PublicationCitationResults
    let scholarName: String

    @State private var sortOrder: CitationContextService.CitingSortOrder = .yearDesc
    @State private var expandedResultId: String?

    private func L(_ key: String) -> String { LocalizationManager.shared.localized(key) }
    private func L(_ key: String, _ args: CVarArg...) -> String {
        String(format: LocalizationManager.shared.localized(key), arguments: args)
    }
    private func sortName(_ o: CitationContextService.CitingSortOrder) -> String {
        switch o {
        case .yearDesc: return L("insights_sort_newest")
        case .yearAsc: return L("insights_sort_oldest")
        case .contextCountDesc: return L("insights_sort_quotes")
        }
    }

    private var sortedPapers: [CitationContextService.BatchCitationResult] {
        let papers = publicationResult.citingPapers
        switch sortOrder {
        case .yearDesc:
            return papers.sorted { ($0.citingYear ?? 0) > ($1.citingYear ?? 0) }
        case .yearAsc:
            return papers.sorted { ($0.citingYear ?? 9999) < ($1.citingYear ?? 9999) }
        case .contextCountDesc:
            return papers.sorted { $0.contexts.count > $1.contexts.count }
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 20) {
                    detailStatCell(value: "\(publicationResult.citingPapers.count)",
                                   label: L("insights_citing_papers"), icon: "doc.on.doc", color: .purple)
                    Divider().frame(height: 40)
                    detailStatCell(value: "\(publicationResult.papersWithContexts)",
                                   label: L("insights_with_quotes"), icon: "text.quote", color: .green)
                    Divider().frame(height: 40)
                    detailStatCell(value: "\(publicationResult.totalContexts)",
                                   label: L("insights_contexts"), icon: "quote.opening", color: .blue)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(L("insights_sort_by"), selection: $sortOrder) {
                    ForEach(CitationContextService.CitingSortOrder.allCases, id: \.self) { order in
                        Text(sortName(order)).tag(order)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Show fetch status if not successful
            if publicationResult.fetchStatus != .success {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: publicationResult.fetchStatus == .notFoundOnSS
                                  ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                                .foregroundColor(.orange)
                            Text(publicationResult.fetchStatus == .notFoundOnSS
                                 ? L("insights_not_found_title")
                                 : publicationResult.fetchStatus == .rateLimited ? L("insights_rate_limited_title") : L("insights_fetch_error_title"))
                                .font(.subheadline).fontWeight(.medium)
                        }
                        Text(publicationResult.fetchStatus == .notFoundOnSS ? L("insights_ss_notfound_msg")
                             : publicationResult.fetchStatus == .rateLimited ? L("insights_ss_ratelimit_msg")
                             : L("insights_ss_error_msg"))
                            .font(.caption).foregroundColor(.secondary)
                        if let detail = publicationResult.fetchErrorDetail {
                            Text(detail)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(L("insights_citing_count", sortedPapers.count)) {
                if sortedPapers.isEmpty && publicationResult.fetchStatus == .success {
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass").font(.title2).foregroundColor(.secondary)
                        Text(L("insights_no_citing"))
                            .font(.subheadline).foregroundColor(.secondary)
                        Text(L("insights_no_citing_desc"))
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 12).frame(maxWidth: .infinity)
                } else if sortedPapers.isEmpty {
                    EmptyView()
                } else {
                    // Context availability summary
                    let withCtx = publicationResult.papersWithContexts
                    let total = sortedPapers.count
                    let noCtx = total - withCtx
                    if noCtx > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle").font(.caption)
                                Text(L("insights_ctx_count", withCtx, total))
                                    .font(.caption).fontWeight(.medium)
                            }
                            .foregroundColor(.secondary)
                            Text(L("insights_ctx_explainer"))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    ForEach(sortedPapers) { result in
                        citingPaperRow(result)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .liquidGlassCanvas()
        .navigationTitle(L("insights_citations_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func citingPaperRow(_ result: CitationContextService.BatchCitationResult) -> some View {
        let isExpanded = expandedResultId == result.id && !result.contexts.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                guard !result.contexts.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedResultId = isExpanded ? nil : result.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Image(systemName: "arrow.turn.down.right").font(.caption).foregroundColor(.accentColor)
                        Text(result.citingPaperTitle)
                            .font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                            .lineLimit(isExpanded ? nil : 2).multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 4) {
                        if !result.citingAuthors.isEmpty {
                            Text(result.citingAuthors.prefix(3).joined(separator: ", ") + (result.citingAuthors.count > 3 ? " et al." : ""))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if let year = result.citingYear {
                            Text(verbatim: "(\(year))").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    if !result.intents.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(result.intents, id: \.self) { intent in
                                intentPill(intent)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        if !result.contexts.isEmpty {
                            Label(L("insights_n_quotes", result.contexts.count),
                                  systemImage: "text.quote")
                                .font(.caption2).foregroundColor(.green)
                        } else {
                            Label(L("insights_no_fulltext"), systemImage: "lock.fill")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if !result.contexts.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded && !result.contexts.isEmpty {
                Divider()
                ForEach(Array(result.contexts.enumerated()), id: \.offset) { idx, quote in
                    quoteCard(quote: quote, index: idx + 1, total: result.contexts.count,
                              paperYear: result.myPaperYear)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func intentPill(_ intent: CitationContext.CitationIntent) -> some View {
        let (label, color): (String, Color) = {
            switch intent {
            case .methodology: return (L("intent_methodology"), .blue)
            case .background: return (L("intent_background"), .gray)
            case .result: return (L("intent_result"), .green)
            case .extends: return (L("intent_extends"), .purple)
            case .unknown: return (L("intent_other"), .secondary)
            }
        }()
        return GlassChip(text: label, tint: color)
    }

    private func quoteCard(quote: String, index: Int, total: Int, paperYear: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if total > 1 {
                Text(L("insights_context_i_of_n", index, total))
                    .font(.caption2).foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
                highlightedQuoteText(quote, paperYear: paperYear)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button {
                    UIPasteboard.general.string = quote
                } label: {
                    Label(L("insights_copy"), systemImage: "doc.on.doc")
                        .font(.caption).foregroundColor(.accentColor)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func highlightedQuoteText(_ text: String, paperYear: Int?) -> Text {
        let markers = findCitationMarkers(in: text, paperYear: paperYear)
        if markers.isEmpty { return Text(text) }

        var attributed = AttributedString(text)
        for marker in markers.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            let startOffset = text.distance(from: text.startIndex, to: marker.range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: marker.range.upperBound)
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
            let attrEnd = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)
            attributed[attrStart..<attrEnd].foregroundColor = .white
            attributed[attrStart..<attrEnd].backgroundColor = .accentColor
            attributed[attrStart..<attrEnd].font = .callout.bold()
        }
        return Text(attributed)
    }

    private struct CitationMarker { let range: Range<String.Index> }

    private func findCitationMarkers(in text: String, paperYear: Int?) -> [CitationMarker] {
        var markers: [CitationMarker] = []
        let lastName = scholarName.components(separatedBy: " ").last ?? scholarName

        if !lastName.isEmpty {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: lastName))\\b[^.;]{0,30}?\\b\\d{4}\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsText = text as NSString
                for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                    if let range = Range(match.range, in: text) {
                        markers.append(CitationMarker(range: range))
                    }
                }
            }
        }

        if markers.isEmpty {
            let pattern = "\\[\\d+(?:[,;\\s]+\\d+)*\\]"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsText = text as NSString
                for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                    if let range = Range(match.range, in: text) {
                        markers.append(CitationMarker(range: range))
                    }
                }
            }
        }
        return markers
    }

    private func detailStatCell(value: String, label: String, icon: String, color: Color) -> some View {
        GlassStatCell(value: value, label: label, systemImage: icon, tint: color)
    }
}

// MARK: - Per-paper analysis list

/// Lists each analyzed publication. Tapping one opens a SEPARATE analysis scoped to
/// just that paper's citing papers (its own research directions, notable citers,
/// venues, top-cited, institutions) — instead of one aggregate across all papers.
private struct PerPaperAnalysisListCard: View {
    let scholar: Scholar
    let pubResults: [CitationContextService.PublicationCitationResults]
    let publicationsForAnalysis: [ScholarPublication]
    private let lm = LocalizationManager.shared

    private var analyzable: [CitationContextService.PublicationCitationResults] {
        pubResults.filter { $0.fetchStatus == .success && !$0.citingPapers.isEmpty }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.localized("analysis_per_paper_title", fallback: "Per-paper analysis"))
                        .font(.headline)
                    Text(lm.localized("analysis_per_paper_subtitle",
                                      fallback: "Tap a paper to analyze who cites it — directions, notable citers, venues, and more."))
                        .font(.caption).foregroundColor(.secondary)
                }

                if analyzable.isEmpty {
                    Text(lm.localized("analysis_per_paper_empty",
                                      fallback: "Analyze papers above first; each one can then be analyzed on its own."))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(Array(analyzable.enumerated()), id: \.element.id) { idx, pub in
                        NavigationLink {
                            PerPaperAnalysisScreen(
                                scholar: scholar,
                                pubResult: pub,
                                publication: publicationsForAnalysis.first { $0.clusterId == pub.id }
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.subheadline).foregroundColor(.accentColor)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pub.publicationTitle)
                                        .font(.subheadline).fontWeight(.medium)
                                        .foregroundColor(.primary).lineLimit(2)
                                    Text(String(format: lm.localized("analysis_n_citing_papers", fallback: "%d citing papers"),
                                                pub.citingPapers.count))
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < analyzable.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
    }
}

/// One paper's isolated analysis screen: wraps AnalysisInsightsSection scoped to a
/// single publication (auto-runs on open if nothing is cached yet).
private struct PerPaperAnalysisScreen: View {
    let scholar: Scholar
    let pubResult: CitationContextService.PublicationCitationResults
    let publication: ScholarPublication?

    /// This single paper's citing-paper set (deduped) for the scoped analysis.
    private var citingPapers: [CitingPaper] {
        var byId: [String: CitingPaper] = [:]
        for cp in pubResult.citingPapers {
            if byId[cp.id] != nil { continue }
            byId[cp.id] = CitingPaper(
                id: cp.id,
                title: cp.citingPaperTitle,
                authors: cp.citingAuthors,
                year: cp.citingYear,
                venue: nil,
                citationCount: nil,
                abstract: cp.contexts.isEmpty ? nil : cp.contexts.joined(separator: " "),
                scholarUrl: nil,
                pdfUrl: nil,
                citedScholarId: scholar.id
            )
        }
        return Array(byId.values)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                AnalysisInsightsSection(
                    scholar: scholar,
                    publications: publication.map { [$0] } ?? [],
                    citingPapers: citingPapers,
                    publicationId: pubResult.id,
                    publicationTitle: pubResult.publicationTitle,
                    autoRun: true
                )
            }
            .padding(GlassMetrics.screenPadding)
        }
        .liquidGlassCanvas()
        .navigationTitle(pubResult.publicationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    CitationInsightsView()
}
