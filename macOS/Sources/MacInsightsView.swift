import SwiftUI
import AppKit

// MARK: - Root (login gate)
struct MacInsightsRootView: View {
    @ObservedObject private var auth = GoogleAuthService.shared

    var body: some View {
        Group {
            if auth.isSignedIn {
                MacInsightsView()
            } else {
                GoogleSignInView()
            }
        }
        .frame(minWidth: 760, minHeight: 600)
    }
}

// MARK: - Insights
struct MacInsightsView: View {
    @State private var scholars: [Scholar] = []
    @State private var selectedScholarId: String = ""
    @State private var analysis: AnalysisResult?
    @State private var isLoading = false
    @State private var loadError: String?

    private var selectedScholar: Scholar? { scholars.first { $0.id == selectedScholarId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                    headerCard

                    if isLoading {
                        GlassCard {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text("Loading analysis…").font(.callout).foregroundColor(.secondary)
                            }
                        }
                    }

                    if let err = loadError {
                        GlassCard {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }

                    if let analysis {
                        resultCards(analysis)
                    } else if !isLoading && loadError == nil && !selectedScholarId.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No analysis yet for this scholar.")
                                    .font(.callout)
                                Text("Run the citation analysis on iOS (or once the macOS run flow lands), and it appears here automatically.")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(GlassMetrics.screenPadding)
            }
            .liquidGlassCanvas()
        }
        .onAppear(perform: load)
    }

    // MARK: Header (scholar picker + account)
    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Scholar").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if scholars.isEmpty {
                    Text("No scholars yet — add one in the menu-bar app first.")
                        .font(.callout).foregroundColor(.secondary)
                } else {
                    Picker("", selection: $selectedScholarId) {
                        ForEach(scholars) { s in
                            Text(s.name).tag(s.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedScholarId) { _ in fetchResult() }

                    HStack {
                        Button { fetchResult() } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(selectedScholarId.isEmpty || isLoading)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Result cards (order matches iOS: notable → venues → directions → top-cited → institutions → score)
    @ViewBuilder
    private func resultCards(_ a: AnalysisResult) -> some View {
        if !a.notableCiters.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionTitle(text: "Notable Citers", icon: "person.crop.circle.badge.checkmark", count: a.notableCiters.count)
                    ForEach(a.notableCiters.prefix(15)) { n in
                        HStack(alignment: .top, spacing: 8) {
                            if let h = n.hIndex {
                                Text("h\(h)").font(.caption.monospacedDigit()).fontWeight(.semibold)
                                    .foregroundColor(.purple).frame(minWidth: 38, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.name).font(.subheadline).fontWeight(.medium)
                                if let aff = n.affiliation { Text(aff).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }

        // Notable venues — tappable drill-down to citing papers.
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                GlassSectionTitle(text: "Notable Venues Citing You", icon: "books.vertical", count: a.topVenues.count)
                if a.topVenues.isEmpty {
                    Text("—").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(a.topVenues.prefix(15)) { v in
                        NavigationLink {
                            MacVenuePapersView(venue: v)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(v.paperCount)").font(.caption.monospacedDigit()).fontWeight(.semibold)
                                    .foregroundColor(.teal).frame(minWidth: 30, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name).font(.subheadline).foregroundColor(.primary).lineLimit(2)
                                    if let t = v.type, !t.isEmpty { Text(t.capitalized).font(.caption2).foregroundColor(.secondary) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        if !a.researchDirections.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionTitle(text: "Research Directions", icon: "rectangle.3.group", count: a.researchDirections.count)
                    ForEach(a.researchDirections) { d in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(d.label).font(.subheadline).fontWeight(.semibold)
                                Spacer()
                                GlassChip(text: "\(d.paperCount)")
                            }
                            if !d.summary.isEmpty { Text(d.summary).font(.caption).foregroundColor(.secondary) }
                        }.padding(.vertical, 3)
                    }
                }
            }
        }

        if !a.topCitedPapers.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionTitle(text: "Top-cited Citers", icon: "star.fill", count: a.topCitedPapers.count)
                    ForEach(a.topCitedPapers.prefix(10)) { p in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(p.citationCount)").font(.caption.monospacedDigit()).fontWeight(.semibold)
                                .foregroundColor(.orange).frame(minWidth: 50, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.subheadline).lineLimit(2)
                                if let v = p.venue { Text(v).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }

        if !a.citingInstitutions.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionTitle(text: "Citing Institutions", icon: "building.columns", count: a.citingInstitutions.count)
                    ForEach(a.citingInstitutions.prefix(15)) { inst in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(inst.paperCount)").font(.caption.monospacedDigit()).fontWeight(.semibold)
                                .frame(minWidth: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inst.name).font(.subheadline).lineLimit(2)
                                if let c = inst.country { Text(c).font(.caption2).foregroundColor(.secondary) }
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }

        // Score your impact entry.
        if let s = selectedScholar {
            NavigationLink {
                MacScoreImpactView(scholarId: s.id, scholarName: s.name)
            } label: {
                GlassCard(tint: .green) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Score your impact").font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                            Text("Rate your academic impact from your citations").font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Data
    private func load() {
        scholars = PreferencesManager.shared.scholars
        if selectedScholarId.isEmpty, let first = scholars.first { selectedScholarId = first.id }
        if !selectedScholarId.isEmpty { fetchResult() }
    }

    private func fetchResult() {
        guard !selectedScholarId.isEmpty else { return }
        isLoading = true
        loadError = nil
        let sid = selectedScholarId
        Task {
            do {
                let result = try await CiteTrackAnalysisService.shared.fetchLatestResult(scholarId: sid)
                await MainActor.run {
                    self.analysis = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.analysis = nil
                    self.isLoading = false
                    self.loadError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Venue drill-down
struct MacVenuePapersView: View {
    let venue: TopVenue
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                Text("\(venue.paperCount) papers here cited you")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(venue.papers) { p in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(p.title).font(.subheadline).fontWeight(.medium)
                            if !p.authors.isEmpty {
                                Text(p.authors.prefix(6).joined(separator: ", ") + (p.authors.count > 6 ? " et al." : ""))
                                    .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                            }
                            HStack(spacing: 12) {
                                if let y = p.year { Text(verbatim: "\(y)").font(.caption2).foregroundColor(.secondary) }
                                if let s = p.scholarUrl, s.hasPrefix("http"), let url = URL(string: s) {
                                    Link(destination: url) { Label("Open", systemImage: "safari").font(.caption2) }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(GlassMetrics.screenPadding)
        }
        .liquidGlassCanvas()
        .navigationTitle(venue.name)
    }
}

// MARK: - Score your impact
struct MacScoreImpactView: View {
    let scholarId: String
    let scholarName: String
    @State private var report: HaiyouScoreReport?
    @State private var isRunning = false
    @State private var loadError: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                if let r = report {
                    GlassCard {
                        VStack(spacing: 8) {
                            Text("\(Int(r.totalScore.rounded())) / \(Int(r.maxTotal))")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                            Text(tierLabel(r.fundingPrediction)).font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(tierColor(r.fundingPrediction))
                        }.frame(maxWidth: .infinity)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionTitle(text: "Impact dimensions")
                            ForEach(r.dimensions) { d in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(d.label).font(.subheadline).fontWeight(.semibold)
                                        Spacer()
                                        Text("\(fmt(d.score)) / \(fmt(d.maxScore))").font(.subheadline.monospacedDigit())
                                    }
                                    ProgressView(value: max(0, min(1, d.score / max(1, d.maxScore))))
                                    if !d.reasoning.isEmpty { Text(d.reasoning).font(.caption).foregroundColor(.secondary) }
                                }.padding(.vertical, 3)
                            }
                        }
                    }
                    if !r.overallAssessment.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 6) {
                                GlassSectionTitle(text: "Overall")
                                Text(r.overallAssessment).font(.callout)
                            }
                        }
                    }
                } else if isRunning {
                    GlassCard { HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Scoring…").foregroundColor(.secondary) } }
                } else {
                    GlassCard {
                        Text("Scoring your academic impact from your citation analysis…")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
                if let err = loadError {
                    GlassCard { Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.orange) }
                }
                if report != nil || loadError != nil {
                    Button { run() } label: { Label("Re-score", systemImage: "arrow.clockwise") }
                        .disabled(isRunning)
                }
            }
            .padding(GlassMetrics.screenPadding)
        }
        .liquidGlassCanvas()
        .navigationTitle("Score your impact")
        .task {
            guard !loaded else { return }
            loaded = true
            await loadCached()
            if report == nil && !isRunning { run() }
        }
    }

    private func loadCached() async {
        report = try? await CiteTrackAnalysisService.shared.fetchLatestHaiyouScore(scholarId: scholarId)
    }

    private func run() {
        isRunning = true
        loadError = nil
        let lang = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh" : "en"
        Task {
            do {
                let r = try await CiteTrackAnalysisService.shared.runHaiyouScore(
                    scholarId: scholarId, scholarName: scholarName,
                    cvText: nil, returnPlanText: nil, representativePapers: [], lang: lang
                )
                await MainActor.run { report = r; isRunning = false }
            } catch {
                await MainActor.run { isRunning = false; loadError = error.localizedDescription }
            }
        }
    }

    private func tierLabel(_ p: String) -> String {
        switch p {
        case "priority": return "Outstanding impact (≥85)"
        case "approved": return "Strong impact (70–84)"
        default: return "Developing impact (<70)"
        }
    }
    private func tierColor(_ p: String) -> Color { p == "priority" ? .green : (p == "approved" ? .orange : .red) }
    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

// MARK: - Window host
final class InsightsWindowController {
    static let shared = InsightsWindowController()
    private var window: NSWindow?

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let host = NSHostingController(rootView: MacInsightsRootView())
        let w = NSWindow(contentViewController: host)
        w.title = "Citation Insights"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 820, height: 640))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
