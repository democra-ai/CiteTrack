import SwiftUI

/// Section embedded in CitationInsightsView that triggers and renders the
/// CiteTrack analysis API (research directions, top-cited, institutions, notable citers).
struct AnalysisInsightsSection: View {
    let scholar: Scholar
    let publications: [ScholarPublication]
    let citingPapers: [CitingPaper]

    @State private var analysis: AnalysisResult?
    @State private var jobStatus: AnalysisJobStatus?
    @State private var isRunning = false
    @State private var loadError: String?
    @State private var cachedLoaded = false
    @State private var enrichProgressText: String?
    /// Job id we last started — kept around so the user can "Refresh" if iOS
    /// gives up polling before the worker is done.
    @State private var pendingJobId: String?
    /// Informational (non-fatal) message when a poll timed out but the job may
    /// still be running server-side.
    @State private var pendingNotice: String?
    @State private var showDeleteConfirm = false
    @State private var runStartedAt: Date?
    @State private var elapsedSeconds = 0

    private let lm = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
            // Header + run-state in one glass card.
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let err = loadError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundColor(.orange)
                    }
                    if let notice = pendingNotice {
                        pendingNoticeRow(notice)
                    }
                    if analysis == nil {
                        if isRunning { progressRow } else { emptyRow }
                    }
                }
            }

            // Each metric is its own glass card once results exist.
            // Order (per product): notable citers → top venues → directions →
            // top-cited → institutions, then the impact-score entry.
            if let analysis {
                VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                    GlassCard {
                        NotableCitersCard(
                            citers: analysis.notableCiters,
                            enrichedCount: analysis.enrichedPapersCount,
                            totalCount: analysis.citingPapersCount
                        )
                    }
                    GlassCard {
                        TopVenuesCard(
                            venues: analysis.topVenues,
                            enrichedCount: analysis.enrichedPapersCount,
                            totalCount: analysis.citingPapersCount
                        )
                    }
                    GlassCard { ResearchDirectionsCard(directions: analysis.researchDirections) }
                    GlassCard { TopCitedPapersCard(papers: analysis.topCitedPapers) }
                    GlassCard {
                        CitingInstitutionsCard(
                            institutions: analysis.citingInstitutions,
                            enrichedCount: analysis.enrichedPapersCount,
                            totalCount: analysis.citingPapersCount
                        )
                    }
                    haiyouEntryCard
                }
                // Smooth reveal when results arrive (vs. popping in abruptly).
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .task(id: scholar.id) {
            await loadCachedIfAvailable()
        }
    }

    private var haiyouEntryCard: some View {
        NavigationLink {
            HaiyouScoreView(scholarId: scholar.id, scholarName: scholar.name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.localized("score_impact_title", fallback: "Score your impact"))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(lm.localized("score_impact_entry_subtitle", fallback: "Rate your academic impact from your citations"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(GlassMetrics.cardPadding)
            .glassSurface(tint: .green)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lm.localized("analysis_title", fallback: "Citation Analysis"))
                    .font(.headline)
                Text(
                    lm.localized(
                        "analysis_subtitle",
                        fallback: "Directions · Top cited · Institutions · Notable citers"
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            if isRunning {
                Button(role: .destructive) {
                    Task { await stop() }
                } label: {
                    Label(lm.localized("analysis_stop", fallback: "Stop"), systemImage: "stop.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .tint(.red)
            } else if analysis != nil {
                HStack(spacing: 14) {
                    Button { Task { await run() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(citingPapers.isEmpty)
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            } else {
                Button { Task { await run() } } label: {
                    Label(lm.localized("analysis_run", fallback: "Run analysis"), systemImage: "sparkles")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .disabled(citingPapers.isEmpty)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            lm.localized("analysis_delete_confirm", fallback: "Delete this analysis and impact score?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(lm.localized("analysis_delete", fallback: "Delete"), role: .destructive) {
                Task { await deleteAnalysis() }
            }
            Button(lm.localized("cancel", fallback: "Cancel"), role: .cancel) {}
        }
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ProgressView(value: Double(jobStatus?.progress ?? 0), total: 100)
                    .frame(width: 90)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stepLabel(enrichProgressText ?? jobStatus?.currentStep))
                        .font(.caption)
                    HStack(spacing: 6) {
                        if let p = jobStatus?.progress {
                            Text("\(p)%").font(.caption2).foregroundColor(.secondary)
                        }
                        if elapsedSeconds > 0 {
                            Text("· \(elapsedSeconds)s").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }
            Text(lm.localized("analysis_cost_hint", fallback: "≈ $0.002 per run · ~24 free runs/day"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// Human-friendly step labels (the backend emits terse internal steps).
    private func stepLabel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return lm.localized("analysis_starting", fallback: "Starting…") }
        if raw.hasPrefix("OpenAlex") { return lm.localized("analysis_step_enrich", fallback: "Enriching via OpenAlex…") }
        switch raw {
        case "enriching": return lm.localized("analysis_step_enrich", fallback: "Enriching via OpenAlex…")
        case "clustering topics": return lm.localized("analysis_step_cluster", fallback: "Clustering research directions…")
        case "ranking top-cited papers": return lm.localized("analysis_step_rank", fallback: "Ranking top-cited papers…")
        case "aggregating institutions": return lm.localized("analysis_step_inst", fallback: "Aggregating institutions…")
        case "finding notable citers": return lm.localized("analysis_step_notable", fallback: "Finding notable citers…")
        default: return raw
        }
    }

    @ViewBuilder
    private func pendingNoticeRow(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.primary)
                Button {
                    Task { await refresh() }
                } label: {
                    Label(
                        lm.localized("analysis_check_result", fallback: "Check result"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(isRunning)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                lm.localized(
                    "analysis_empty",
                    fallback: "Tap Run analysis to see research directions, top-cited papers, institutions, and notable citers."
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
            if citingPapers.isEmpty {
                Text(
                    lm.localized(
                        "analysis_no_citing",
                        fallback: "Load citing papers first by running an Insights batch above."
                    )
                )
                .font(.caption2)
                .foregroundColor(.orange)
            } else {
                Text(String(format: lm.localized("analysis_paper_count", fallback: "%d citing papers ready"), citingPapers.count))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @MainActor
    private func loadCachedIfAvailable() async {
        guard !cachedLoaded else { return }
        cachedLoaded = true
        do {
            if let cached = try await CiteTrackAnalysisService.shared.fetchLatestResult(scholarId: scholar.id) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                    analysis = cached
                }
            }
        } catch {
            // silent: cached fetch is best-effort
        }
    }

    @MainActor
    private func run() async {
        guard !citingPapers.isEmpty else {
            loadError = lm.localized("analysis_no_citing", fallback: "No citing papers loaded.")
            return
        }
        // Cap the set sent for AI analysis. On-device OpenAlex enrichment and the worker's
        // embedding/clustering both scale with paper count; a very large set blows past the
        // Cloudflare worker's wall-time so the job never finishes and the poll times out.
        // The top slice is a representative sample for directions / top-cited / institutions / citers.
        let analysisPapers = Array(citingPapers.prefix(200))
        isRunning = true
        loadError = nil
        pendingNotice = nil
        runStartedAt = Date()
        elapsedSeconds = 0
        enrichProgressText = lm.localized("analysis_enrich_running", fallback: "Looking up OpenAlex…")
        defer {
            isRunning = false
            enrichProgressText = nil
        }

        let enriched = await OpenAlexEnrichmentClient.shared.enrich(
            citingPapers: analysisPapers,
            concurrency: 6,
            progress: { completed, total in
                Task { @MainActor in
                    let fmt = self.lm.localized("analysis_enrich_progress", fallback: "OpenAlex %d / %d")
                    self.enrichProgressText = String(format: fmt, completed, total)
                    self.bumpElapsed()
                }
            }
        )
        enrichProgressText = nil

        // Step + poll separately so we can recover the jobId on timeout
        // and offer a Refresh affordance instead of a fatal error.
        let jobId: String
        do {
            jobId = try await CiteTrackAnalysisService.shared.startAnalysis(
                scholar: scholar,
                publications: publications,
                citingPapers: analysisPapers,
                enrichedCitingPapers: enriched.isEmpty ? nil : enriched,
                lang: lm.currentLanguage == .chinese ? "zh" : "en"
            )
        } catch {
            loadError = error.localizedDescription
            return
        }
        pendingJobId = jobId

        do {
            let final = try await CiteTrackAnalysisService.shared.pollUntilDone(
                jobId: jobId,
                progress: { status in
                    Task { @MainActor in
                        self.jobStatus = status
                        self.bumpElapsed()
                    }
                }
            )
            if final.status == "cancelled" {
                pendingNotice = lm.localized("analysis_cancelled", fallback: "Analysis cancelled.")
                pendingJobId = nil
                return
            }
            if final.status == "error" {
                loadError = final.error ?? lm.localized("analysis_failed", fallback: "Analysis failed")
                return
            }
            if let result = try await CiteTrackAnalysisService.shared.fetchLatestResult(scholarId: scholar.id) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    analysis = result
                }
                pendingJobId = nil
                pendingNotice = nil
            }
        } catch AnalysisServiceError.timeout {
            // Non-fatal: the worker may still be running. Offer Refresh.
            pendingNotice = lm.localized(
                "analysis_still_running",
                fallback: "Analysis is taking longer than expected. The worker may still be running — tap Check result to fetch the latest."
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func bumpElapsed() {
        guard let start = runStartedAt else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(start))
    }

    @MainActor
    private func stop() async {
        guard let jobId = pendingJobId else {
            isRunning = false
            return
        }
        do {
            try await CiteTrackAnalysisService.shared.cancelJob(jobId: jobId)
        } catch {
            // best-effort; the poll loop will also stop on cancelled status
        }
        isRunning = false
        pendingNotice = lm.localized("analysis_cancelled", fallback: "Analysis cancelled.")
        pendingJobId = nil
    }

    @MainActor
    private func deleteAnalysis() async {
        loadError = nil
        do {
            try await CiteTrackAnalysisService.shared.deleteAnalysis(scholarId: scholar.id)
            analysis = nil
            jobStatus = nil
            pendingJobId = nil
            pendingNotice = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func refresh() async {
        isRunning = true
        loadError = nil
        defer { isRunning = false }

        // 1) If we have a pending job, check its current status first.
        if let jobId = pendingJobId {
            do {
                let status = try await CiteTrackAnalysisService.shared.fetchJobStatus(jobId: jobId)
                jobStatus = status
                if status.status == "error" {
                    loadError = status.error ?? lm.localized("analysis_failed", fallback: "Analysis failed")
                    pendingJobId = nil
                    pendingNotice = nil
                    return
                }
                if status.status != "done" {
                    let fmt = lm.localized("analysis_still_running_progress", fallback: "Still running (%@, %d%%). Try again in a moment.")
                    pendingNotice = String(format: fmt, status.currentStep ?? "...", status.progress)
                    return
                }
            } catch {
                // fall through to result fetch
            }
        }

        // 2) Job is done (or unknown) — fetch latest result.
        do {
            if let result = try await CiteTrackAnalysisService.shared.fetchLatestResult(scholarId: scholar.id) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    analysis = result
                }
                pendingJobId = nil
                pendingNotice = nil
            } else {
                pendingNotice = lm.localized(
                    "analysis_no_result_yet",
                    fallback: "No result yet — the worker may still be processing. Try again shortly."
                )
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Card: Research Directions

private struct ResearchDirectionsCard: View {
    let directions: [ResearchDirection]
    private let lm = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                lm.localized("analysis_card_directions", fallback: "Research Directions"),
                icon: "rectangle.3.group",
                count: directions.count
            )
            if directions.isEmpty {
                Text(lm.localized("analysis_card_empty", fallback: "—"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(directions) { d in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(d.label).font(.subheadline).fontWeight(.semibold)
                            Spacer()
                            GlassChip(text: "\(d.paperCount)", tint: .secondary)
                        }
                        if !d.summary.isEmpty {
                            Text(d.summary).font(.caption).foregroundColor(.secondary)
                        }
                        if !d.keywords.isEmpty {
                            FlowLayout(items: d.keywords) { kw in
                                GlassChip(text: kw, tint: .blue)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Card: Top cited

private struct TopCitedPapersCard: View {
    let papers: [TopCitedPaper]
    private let lm = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                lm.localized("analysis_card_top_cited", fallback: "Top-cited Citers"),
                icon: "star.fill",
                count: papers.count
            )
            if papers.isEmpty {
                Text(lm.localized("analysis_card_empty", fallback: "—"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(papers.prefix(10)) { p in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(p.citationCount)")
                            .font(.caption.monospacedDigit())
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .frame(minWidth: 50, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(.subheadline).lineLimit(2)
                            HStack(spacing: 6) {
                                if let y = p.year {
                                    Text(String(y)).font(.caption2).foregroundColor(.secondary)
                                }
                                if let v = p.venue {
                                    Text(v).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                            if !p.authors.isEmpty {
                                Text(p.authors.prefix(3).joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Card: Institutions

private struct CitingInstitutionsCard: View {
    let institutions: [CitingInstitution]
    let enrichedCount: Int
    let totalCount: Int
    private let lm = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                lm.localized("analysis_card_institutions", fallback: "Citing Institutions"),
                icon: "building.columns",
                count: institutions.count
            )
            if institutions.isEmpty {
                degradedNotice
            } else {
                ForEach(institutions.prefix(15)) { inst in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(inst.paperCount)")
                            .font(.caption.monospacedDigit())
                            .fontWeight(.semibold)
                            .frame(minWidth: 30, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inst.name).font(.subheadline).lineLimit(2)
                            HStack(spacing: 6) {
                                if let c = inst.country {
                                    Text(c).font(.caption2).foregroundColor(.secondary)
                                }
                                if let t = inst.type {
                                    Text(t).font(.caption2).foregroundColor(.secondary)
                                }
                                Text(String(format: lm.localized("analysis_authors_n", fallback: "%d authors"), inst.uniqueAuthorCount))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var degradedNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lm.localized("analysis_card_empty", fallback: "—"))
                .font(.caption).foregroundColor(.secondary)
            if enrichedCount == 0 && totalCount > 0 {
                Text(
                    lm.localized(
                        "analysis_enrichment_unavailable",
                        fallback: "Enrichment data unavailable. Institutions appear once papers are matched to OpenAlex."
                    )
                )
                .font(.caption2)
                .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Card: Notable citers

private struct NotableCitersCard: View {
    let citers: [NotableCiter]
    let enrichedCount: Int
    let totalCount: Int
    private let lm = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                lm.localized("analysis_card_notable", fallback: "Notable Citers"),
                icon: "person.crop.circle.badge.checkmark",
                count: citers.count
            )
            if citers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lm.localized("analysis_card_empty", fallback: "—"))
                        .font(.caption).foregroundColor(.secondary)
                    if enrichedCount == 0 && totalCount > 0 {
                        Text(
                            lm.localized(
                                "analysis_enrichment_unavailable",
                                fallback: "Enrichment data unavailable. Notable scholars appear once authors are matched to OpenAlex."
                            )
                        )
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }
            } else {
                ForEach(citers.prefix(15)) { n in
                    HStack(alignment: .top, spacing: 8) {
                        if let h = n.hIndex {
                            Text("h\(h)")
                                .font(.caption.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                                .frame(minWidth: 36, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.name).font(.subheadline).fontWeight(.medium)
                            if let aff = n.affiliation {
                                Text(aff).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                            if let cited = n.citedByCount {
                                Text(String(format: lm.localized("analysis_citedby_n", fallback: "%d total citations"), cited))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Card: Top venues

private struct TopVenuesCard: View {
    let venues: [TopVenue]
    let enrichedCount: Int
    let totalCount: Int
    private let lm = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                lm.localized("analysis_card_venues", fallback: "Top Venues Citing You"),
                icon: "books.vertical",
                count: venues.count
            )
            if venues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lm.localized("analysis_card_empty", fallback: "—"))
                        .font(.caption).foregroundColor(.secondary)
                    if enrichedCount == 0 && totalCount > 0 {
                        Text(
                            lm.localized(
                                "analysis_venues_unavailable",
                                fallback: "Venues appear once citing papers are matched to OpenAlex."
                            )
                        )
                        .font(.caption2).foregroundColor(.orange)
                    }
                }
            } else {
                ForEach(venues.prefix(15)) { v in
                    NavigationLink {
                        VenueCitingPapersView(venue: v)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(v.paperCount)")
                                .font(.caption.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundColor(.teal)
                                .frame(minWidth: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name).font(.subheadline).foregroundColor(.primary).lineLimit(2)
                                if let t = v.type, !t.isEmpty {
                                    Text(venueTypeLabel(t))
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func venueTypeLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "journal": return lm.localized("venue_type_journal", fallback: "Journal")
        case "conference": return lm.localized("venue_type_conference", fallback: "Conference")
        case "repository": return lm.localized("venue_type_repository", fallback: "Repository")
        case "book series", "book": return lm.localized("venue_type_book", fallback: "Book series")
        default: return raw.capitalized
        }
    }
}

// MARK: - Venue drill-down: which papers in this venue cited the scholar

private struct VenueCitingPapersView: View {
    let venue: TopVenue
    private let lm = LocalizationManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                Text(String(format: lm.localized("analysis_venue_cited_n", fallback: "%d papers here cited you"), venue.paperCount))
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(venue.papers) { p in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(p.title)
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.primary)
                            if !p.authors.isEmpty {
                                Text(p.authors.prefix(6).joined(separator: ", ")
                                     + (p.authors.count > 6 ? " " + "et_al".localized : ""))
                                    .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                            }
                            HStack(spacing: 12) {
                                if let y = p.year {
                                    Text(verbatim: "\(y)").font(.caption2).foregroundColor(.secondary)
                                }
                                if let link = venueURL(p.scholarUrl) {
                                    Link(destination: link) {
                                        Label(lm.localized("open_in_browser", fallback: "Open"), systemImage: "safari")
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(GlassMetrics.screenPadding)
        }
        .liquidGlassCanvas()
        .navigationTitle(venue.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func venueURL(_ s: String?) -> URL? {
        guard let s, s.hasPrefix("http") else { return nil }
        return URL(string: s)
    }
}

// MARK: - Helpers

private func sectionTitle(_ text: String, icon: String, count: Int) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon).font(.caption).foregroundColor(.secondary)
        Text(text).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
        if count > 0 {
            Text("(\(count))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        Spacer()
    }
    .textCase(.uppercase)
}

/// Minimal flow layout for keyword chips (iOS 16+).
/// Wraps chips onto multiple rows and reports the correct total height, so it
/// never overflows into the view below. Built on the iOS 16 Layout protocol.
private struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        FlowStack(spacing: 4, lineSpacing: 4) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

private struct FlowStack: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
