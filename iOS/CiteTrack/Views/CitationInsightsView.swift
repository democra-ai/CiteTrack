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
    @State private var loadError: String?
    @State private var hasAuthorInfo = false
    @State private var pickerRoleFilter: CitationContextService.AuthorRole? = nil

    var body: some View {
        NavigationView {
            Group {
                if auth.isSignedIn {
                    insightsBody
                } else {
                    signInGate
                }
            }
            .navigationTitle("Citation Insights")
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

    /// IDs of publications that have already been analyzed and saved
    private var alreadyAnalyzedIds: Set<String> {
        Set(publicationResults.map { $0.id })
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

            // If still too many missing, force fresh fetch from GS
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

            // If many authors missing, force fresh fetch
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
                Text("Citation Insights")
                    .font(.title2).fontWeight(.bold)
                Text("See how others cite your work")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Text("Discover how researchers worldwide cite your work — see the exact passages where your papers are referenced.")
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: { showSignIn = true }) {
                GoogleSignInButton { showSignIn = true }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Main Content

    private var insightsBody: some View {
        List {
            // 1. Scholar picker
            Section {
                scholarPicker
            }

            // 2. Publication selection + Analyze (one section)
            Section {
                publicationSelectionRow
            }

            // 3. Progress (when running)
            if contextService.batchProgress.isRunning {
                Section {
                    progressView
                }
            }

            // 4. Results — per-publication drill-down (show all ever-analyzed publications)
            if hasFetched && !contextService.batchProgress.isRunning {
                Section {
                    summaryCard
                }

                Section("Your Publications (\(publicationResults.count))") {
                    if publicationResults.isEmpty {
                        emptyResultsRow
                    } else {
                        ForEach(publicationResults) { pubResult in
                            NavigationLink {
                                PublicationCitationDetailView(
                                    publicationResult: pubResult,
                                    scholarName: selectedScholarName
                                )
                            } label: {
                                publicationResultRow(pubResult)
                            }
                        }
                    }
                }

                if !contextService.batchProgress.errors.isEmpty {
                    Section("Issues") {
                        ForEach(contextService.batchProgress.errors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Scholar Picker

    private var scholarPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Scholar")
                .font(.caption).foregroundColor(.secondary).textCase(.uppercase)

            if dataManager.scholars.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus").foregroundColor(.secondary)
                    Text("Add a scholar in the Dashboard first.")
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
                    Text("\(citations) citations")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
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
            Text("Select Publications")
                .font(.caption).foregroundColor(.secondary).textCase(.uppercase)

            if publicationsWithAuthors.isEmpty {
                if isFetchingAuthors {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading publications...")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if let error = loadError {
                    VStack(spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                        Button("Retry") {
                            if let sid = selectedScholarId {
                                loadPublications(forScholar: sid)
                            }
                        }
                        .font(.subheadline)
                    }
                } else if selectedScholarId != nil {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text("Preparing...")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Select a scholar above to load publications")
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
                            HStack(spacing: 3) {
                                Image(systemName: role.icon).font(.caption2)
                                Text("\(selectedInRole)/\(pubs.count)")
                                    .font(.caption).fontWeight(.medium)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(role.color.opacity(0.12))
                            .foregroundColor(role.color)
                            .cornerRadius(6)
                        }
                    }
                }

                HStack {
                    Text("\(selectedPubIds.count)/\(publicationsWithAuthors.count) selected")
                        .font(.subheadline)
                    Spacer()
                }

                // Two buttons: Choose + Analyze
                HStack(spacing: 12) {
                    Button {
                        showPublicationPicker = true
                    } label: {
                        Label("Choose", systemImage: "checklist")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        startBatchFetch()
                    } label: {
                        let count = newToAnalyzeCount
                        Label(
                            count > 0 ? "Analyze (\(count))" : "All Analyzed",
                            systemImage: "magnifyingglass"
                        )
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newToAnalyzeCount == 0 || contextService.batchProgress.isRunning)
                }

                // Show how many already analyzed
                if !publicationResults.isEmpty {
                    Text("\(publicationResults.count) publication\(publicationResults.count == 1 ? "" : "s") analyzed")
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
                                roleFilterChip(role: nil, label: "All", count: publicationsWithAuthors.count,
                                               icon: "person.3", color: .accentColor)
                                ForEach(allRoles, id: \.self) { role in
                                    let count = grouped[role]?.count ?? 0
                                    if count > 0 {
                                        roleFilterChip(role: role, label: role.displayName, count: count,
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
                            Text(selectedPubIds.isSuperset(of: filteredIds) ? "Deselect All" : "Select All")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(selectedPubIds.intersection(filteredIds).count)/\(filteredIds.count)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section("Publications (\(pickerFilteredPubs.count))") {
                    ForEach(pickerFilteredPubs) { pub in
                        let role = pub.detectRole(scholarName: selectedScholarName)
                        publicationRow(pub, role: role)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Publications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showPublicationPicker = false }
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
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption).fontWeight(.medium)
                Text("(\(count))").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isActive ? color.opacity(0.2) : Color(.systemGray6))
            .foregroundColor(isActive ? color : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? color : Color.clear, lineWidth: 1)
            )
        }
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
                            Text("\(year)").font(.caption2).foregroundColor(.secondary)
                        }
                        if let count = pub.citationCount, count > 0 {
                            Text("Cited by \(count)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        if hasAuthorInfo && role != .unknown {
                            Text(role.displayName)
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
        let display = authors.prefix(5)
        let suffix = authors.count > 5 ? " et al." : ""

        return HStack(spacing: 0) {
            ForEach(Array(display.enumerated()), id: \.offset) { idx, author in
                let isScholar = CitationContextService.PublicationWithAuthors.namesMatch(author, name)
                if idx > 0 {
                    Text(", ").font(.caption).foregroundColor(.secondary)
                }
                Text(author)
                    .font(.caption)
                    .fontWeight(isScholar ? .bold : .regular)
                    .foregroundColor(isScholar ? role.color : .secondary)
            }
            if !suffix.isEmpty {
                Text(suffix).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        let progress = contextService.batchProgress
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("Analyzing citations...")
                    .font(.subheadline).fontWeight(.medium)
                Spacer()
                Text("\(progress.currentPaperIndex)/\(progress.totalPapers)")
                    .font(.caption).foregroundColor(.secondary)
            }
            ProgressView(value: progress.fraction).tint(.accentColor)
            Text(progress.currentPaperTitle)
                .font(.caption).foregroundColor(.secondary).lineLimit(1)
            if progress.totalContextsFound > 0 {
                Text("\(progress.totalContextsFound) citation contexts found so far")
                    .font(.caption).foregroundColor(.green)
            }
            if progress.successCount > 0 || progress.notFoundCount > 0 {
                HStack(spacing: 12) {
                    if progress.successCount > 0 {
                        Label("\(progress.successCount) done", systemImage: "checkmark.circle")
                            .font(.caption2).foregroundColor(.green)
                    }
                    if progress.notFoundCount > 0 {
                        Label("\(progress.notFoundCount) not found", systemImage: "exclamationmark.triangle")
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
            statCell(value: "\(publicationResults.count)", label: "Papers Analyzed",
                     icon: "doc.text.magnifyingglass", color: .blue)
            Divider().frame(height: 40)
            statCell(value: "\(totalCiting)", label: "Citing Papers",
                     icon: "doc.on.doc", color: .purple)
            Divider().frame(height: 40)
            statCell(value: "\(totalContexts)", label: "Contexts",
                     icon: "text.quote", color: .green)
        }
        .padding(.vertical, 8)
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundColor(color)
            Text(value).font(.title2).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
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
                    Text("\(year)")
                        .font(.caption).foregroundColor(.secondary)
                }
                if pubResult.fetchStatus == .notFoundOnSS {
                    Label("Not on Semantic Scholar", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange)
                } else if pubResult.fetchStatus == .rateLimited {
                    Label("Rate limited", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundColor(.orange)
                } else if pubResult.fetchStatus == .error {
                    Label("Error", systemImage: "xmark.circle")
                        .font(.caption).foregroundColor(.red)
                } else {
                    Label("\(pubResult.citingPapers.count) citing", systemImage: "doc.on.doc")
                        .font(.caption).foregroundColor(.purple)
                    if pubResult.totalContexts > 0 {
                        Label("\(pubResult.totalContexts) quotes", systemImage: "text.quote")
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
            Text("No citation data found.").font(.subheadline).foregroundColor(.secondary)
            Text("Selected publications may not be indexed on Semantic Scholar, or have no citations with context.")
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

            // Merge: keep existing results + add new ones
            var merged = publicationResults
            for result in newResults {
                if !merged.contains(where: { $0.id == result.id }) {
                    merged.append(result)
                }
            }

            publicationResults = merged
            hasFetched = true

            // Persist the merged results
            contextService.savePublicationResults(merged, forScholar: scholarId)
        }
    }
}

// MARK: - Publication Citation Detail View

struct PublicationCitationDetailView: View {
    let publicationResult: CitationContextService.PublicationCitationResults
    let scholarName: String

    @State private var sortOrder: CitationContextService.CitingSortOrder = .yearDesc
    @State private var expandedResultId: String?

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
                                   label: "Citing Papers", icon: "doc.on.doc", color: .purple)
                    Divider().frame(height: 40)
                    detailStatCell(value: "\(publicationResult.papersWithContexts)",
                                   label: "With Quotes", icon: "text.quote", color: .green)
                    Divider().frame(height: 40)
                    detailStatCell(value: "\(publicationResult.totalContexts)",
                                   label: "Contexts", icon: "quote.opening", color: .blue)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(CitationContextService.CitingSortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
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
                                 ? "Not Found on Semantic Scholar"
                                 : publicationResult.fetchStatus == .rateLimited ? "Rate Limited" : "Fetch Error")
                                .font(.subheadline).fontWeight(.medium)
                        }
                        Text(publicationResult.fetchStatus.displayMessage)
                            .font(.caption).foregroundColor(.secondary)
                        if let detail = publicationResult.fetchErrorDetail {
                            Text(detail)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Citing Papers (\(sortedPapers.count))") {
                if sortedPapers.isEmpty && publicationResult.fetchStatus == .success {
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass").font(.title2).foregroundColor(.secondary)
                        Text("No citing papers found.")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("This paper may have citations that Semantic Scholar hasn't indexed yet.")
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
                                Text("\(withCtx)/\(total) papers have citation context")
                                    .font(.caption).fontWeight(.medium)
                            }
                            .foregroundColor(.secondary)
                            Text("Papers without context: Semantic Scholar only extracts verbatim quotes from open-access full texts. Paywalled or non-indexed papers won't have citation context.")
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
        .navigationTitle("Citations")
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
                            Text("(\(year))").font(.caption).foregroundColor(.secondary)
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
                            Label("\(result.contexts.count) quote\(result.contexts.count == 1 ? "" : "s")",
                                  systemImage: "text.quote")
                                .font(.caption2).foregroundColor(.green)
                        } else {
                            Label("No full text access", systemImage: "lock.fill")
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
            case .methodology: return ("Methodology", .blue)
            case .background: return ("Background", .gray)
            case .result: return ("Result", .green)
            case .extends: return ("Extends", .purple)
            case .unknown: return ("Other", .secondary)
            }
        }()
        return Text(label)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func quoteCard(quote: String, index: Int, total: Int, paperYear: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if total > 1 {
                Text("Context \(index) of \(total)")
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
                    Label("Copy", systemImage: "doc.on.doc")
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
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundColor(color)
            Text(value).font(.title2).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    CitationInsightsView()
}
