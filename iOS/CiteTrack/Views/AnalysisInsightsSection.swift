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

    private let lm = LocalizationManager.shared

    var body: some View {
        Section {
            header
            if let err = loadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange)
            }
            if let analysis {
                ResearchDirectionsCard(directions: analysis.researchDirections)
                TopCitedPapersCard(papers: analysis.topCitedPapers)
                CitingInstitutionsCard(
                    institutions: analysis.citingInstitutions,
                    enrichedCount: analysis.enrichedPapersCount,
                    totalCount: analysis.citingPapersCount
                )
                NotableCitersCard(
                    citers: analysis.notableCiters,
                    enrichedCount: analysis.enrichedPapersCount,
                    totalCount: analysis.citingPapersCount
                )
            } else if isRunning {
                progressRow
            } else {
                emptyRow
            }
        } header: {
            Text(lm.localized("analysis_section_header", fallback: "AI Analysis"))
                .textCase(.uppercase)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .task(id: scholar.id) {
            await loadCachedIfAvailable()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
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
            Button(action: { Task { await run() } }) {
                if isRunning {
                    ProgressView()
                } else if analysis == nil {
                    Label(
                        lm.localized("analysis_run", fallback: "Run analysis"),
                        systemImage: "sparkles"
                    )
                    .font(.subheadline)
                } else {
                    Label(
                        lm.localized("analysis_refresh", fallback: "Refresh"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.subheadline)
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRunning || citingPapers.isEmpty)
        }
        .padding(.vertical, 4)
    }

    private var progressRow: some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(jobStatus?.progress ?? 0), total: 100)
                .frame(width: 80)
            VStack(alignment: .leading, spacing: 2) {
                Text(enrichProgressText ?? jobStatus?.currentStep ?? lm.localized("analysis_starting", fallback: "Starting…"))
                    .font(.caption)
                if let p = jobStatus?.progress {
                    Text("\(p)%").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
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
                analysis = cached
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
        isRunning = true
        loadError = nil
        enrichProgressText = lm.localized("analysis_enrich_running", fallback: "Looking up OpenAlex…")
        defer {
            isRunning = false
            enrichProgressText = nil
        }

        let enriched = await OpenAlexEnrichmentClient.shared.enrich(
            citingPapers: citingPapers,
            concurrency: 4,
            progress: { completed, total in
                Task { @MainActor in
                    let fmt = self.lm.localized("analysis_enrich_progress", fallback: "OpenAlex %d / %d")
                    self.enrichProgressText = String(format: fmt, completed, total)
                }
            }
        )
        enrichProgressText = nil

        do {
            let result = try await CiteTrackAnalysisService.shared.runAnalysis(
                scholar: scholar,
                publications: publications,
                citingPapers: citingPapers,
                enrichedCitingPapers: enriched.isEmpty ? nil : enriched,
                progress: { status in
                    Task { @MainActor in self.jobStatus = status }
                }
            )
            analysis = result
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
                            Text("\(d.paperCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if !d.summary.isEmpty {
                            Text(d.summary).font(.caption).foregroundColor(.secondary)
                        }
                        if !d.keywords.isEmpty {
                            FlowLayout(items: d.keywords) { kw in
                                Text(kw)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
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
private struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
        .frame(minHeight: 22)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item == items.last {
                            width = 0
                        } else {
                            width -= d.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}
