import SwiftUI

/// "Score your impact" — simulated multi-dimension impact scoring for a scholar,
/// built on their citation-analysis data. Runs automatically on open; no manual
/// inputs required. Requires that the citation analysis has already been run.
struct HaiyouScoreView: View {
    let scholarId: String
    let scholarName: String

    @State private var report: HaiyouScoreReport?
    @State private var jobStatus: AnalysisJobStatus?
    @State private var isRunning = false
    @State private var loadError: String?
    @State private var cachedLoaded = false

    private let lm = LocalizationManager.shared

    var body: some View {
        List {
            if let report {
                scoreHeaderSection(report)
                dimensionsSection(report)
                assessmentSection(report)
            } else if isRunning {
                Section { runningRow }
            } else {
                Section {
                    Text(lm.localized("score_impact_intro", fallback: "Scoring your academic impact from your citation analysis across several dimensions…"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            // First run is automatic on open; offer a re-score once there's a result or an error.
            if report != nil || loadError != nil {
                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            if isRunning {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(lm.localized("score_impact_rescore", fallback: "Re-score"))
                        }
                    }
                    .disabled(isRunning)
                }
            }

            if let err = loadError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .liquidGlassCanvas()
        .navigationTitle(lm.localized("score_impact_title", fallback: "Score your impact"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scholarId) {
            await loadCached()
            if report == nil && !isRunning {
                await run()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func scoreHeaderSection(_ r: HaiyouScoreReport) -> some View {
        Section {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(1, r.totalScore / r.maxTotal))
                        .stroke(
                            scoreColor(r.totalScore / r.maxTotal),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(r.totalScore.rounded()))")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("/ \(Int(r.maxTotal))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 130, height: 130)
                .padding(.top, 6)

                fundingBadge(r.fundingPrediction)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func dimensionsSection(_ r: HaiyouScoreReport) -> some View {
        Section(lm.localized("score_impact_dimensions", fallback: "Impact dimensions")) {
            ForEach(r.dimensions) { d in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(d.label).font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Text("\(fmt(d.score)) / \(fmt(d.maxScore))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(scoreColor(d.score / max(1, d.maxScore)))
                        confidenceTag(d.confidence)
                    }
                    ProgressView(value: max(0, min(1, d.score / max(1, d.maxScore))))
                        .tint(scoreColor(d.score / max(1, d.maxScore)))
                    if !d.reasoning.isEmpty {
                        Text(d.reasoning)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !d.suggestions.isEmpty {
                        ForEach(Array(d.suggestions.prefix(2).enumerated()), id: \.offset) { _, s in
                            Label(s, systemImage: "arrow.up.right.circle")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func assessmentSection(_ r: HaiyouScoreReport) -> some View {
        if !r.overallAssessment.isEmpty || !r.topSuggestions.isEmpty {
            Section(lm.localized("score_impact_overall", fallback: "Overall & top suggestions")) {
                if !r.overallAssessment.isEmpty {
                    Text(r.overallAssessment)
                        .font(.callout)
                }
                ForEach(Array(r.topSuggestions.enumerated()), id: \.offset) { i, s in
                    Label("\(i + 1). \(s)", systemImage: "lightbulb")
                        .font(.caption)
                }
            }
        }
    }

    private var runningRow: some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(jobStatus?.progress ?? 0), total: 100)
                .frame(width: 90)
            Text(jobStatus?.currentStep ?? lm.localized("score_impact_running", fallback: "Scoring…"))
                .font(.caption)
            Spacer()
        }
    }

    // MARK: - Bits

    private func fundingBadge(_ p: String) -> some View {
        let (text, color): (String, Color) = {
            switch p {
            case "priority": return (lm.localized("score_impact_tier_top", fallback: "Outstanding impact (≥85)"), .green)
            case "approved": return (lm.localized("score_impact_tier_strong", fallback: "Strong impact (70–84)"), .orange)
            default: return (lm.localized("score_impact_tier_dev", fallback: "Developing impact (<70)"), .red)
            }
        }()
        return Text(text)
            .font(.subheadline).fontWeight(.bold)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func confidenceTag(_ c: String) -> some View {
        let color: Color = c == "high" ? .green : (c == "medium" ? .orange : .secondary)
        return Text(c)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func scoreColor(_ ratio: Double) -> Color {
        if ratio >= 0.85 { return .green }
        if ratio >= 0.7 { return .orange }
        return .red
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: - Actions
    // (Manual CV / return-plan / representative-paper inputs were removed — the
    //  score now runs automatically from the citation-analysis data on open.)

    @MainActor
    private func loadCached() async {
        guard !cachedLoaded else { return }
        cachedLoaded = true
        do {
            if let cached = try await CiteTrackAnalysisService.shared.fetchLatestHaiyouScore(scholarId: scholarId) {
                report = cached
            }
        } catch {
            // best-effort
        }
    }

    @MainActor
    private func run() async {
        isRunning = true
        loadError = nil
        defer { isRunning = false }
        do {
            let r = try await CiteTrackAnalysisService.shared.runHaiyouScore(
                scholarId: scholarId,
                scholarName: scholarName,
                cvText: nil,
                returnPlanText: nil,
                representativePapers: [],
                progress: { status in
                    Task { @MainActor in self.jobStatus = status }
                }
            )
            report = r
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// (HaiyouInputSheet removed — impact scoring now runs automatically with no manual inputs.)
