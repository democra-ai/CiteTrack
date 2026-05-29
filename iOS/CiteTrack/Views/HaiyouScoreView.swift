import SwiftUI

/// 海优（国家自然科学基金优秀青年科学基金项目·海外）模拟评分页面。
/// Requires that the citation analysis has already been run for this scholar.
struct HaiyouScoreView: View {
    let scholarId: String
    let scholarName: String

    @State private var report: HaiyouScoreReport?
    @State private var jobStatus: AnalysisJobStatus?
    @State private var isRunning = false
    @State private var loadError: String?
    @State private var cachedLoaded = false

    // Optional inputs that improve dimensions 1 & 5.
    @State private var cvText = ""
    @State private var returnPlanText = ""
    @State private var repPapers: [RepresentativePaperInput] = []
    @State private var showInputSheet = false

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
                    Text(lm.localized("haiyou_intro", fallback: "基于你的引用分析数据，按海优五维评审体系（15+30+20+20+15=100）模拟打分。建议先填写简历与回国设想以提升维度1/5的评分准确度。"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button {
                    showInputSheet = true
                } label: {
                    Label(
                        lm.localized("haiyou_edit_inputs", fallback: "填写简历 / 回国设想 / 代表作"),
                        systemImage: "square.and.pencil"
                    )
                }
                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if isRunning {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text(
                            report == nil
                                ? lm.localized("haiyou_run", fallback: "开始模拟评分")
                                : lm.localized("haiyou_rescore", fallback: "重新评分")
                        )
                    }
                }
                .disabled(isRunning)
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
        .navigationTitle(lm.localized("haiyou_title", fallback: "海优模拟评分"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInputSheet) {
            HaiyouInputSheet(
                cvText: $cvText,
                returnPlanText: $returnPlanText,
                repPapers: $repPapers
            )
        }
        .task(id: scholarId) {
            await loadCached()
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

                if !r.dataCompleteness.hasCvText || !r.dataCompleteness.hasReturnPlan {
                    Text(lm.localized("haiyou_incomplete", fallback: "未提供简历/回国设想，维度1/5为低置信度估算。填写后重新评分更准确。"))
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func dimensionsSection(_ r: HaiyouScoreReport) -> some View {
        Section(lm.localized("haiyou_dimensions", fallback: "五维评分")) {
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
            Section(lm.localized("haiyou_overall", fallback: "整体评价与优先建议")) {
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
            Text(jobStatus?.currentStep ?? lm.localized("haiyou_running", fallback: "评审专家打分中…"))
                .font(.caption)
            Spacer()
        }
    }

    // MARK: - Bits

    private func fundingBadge(_ p: String) -> some View {
        let (text, color): (String, Color) = {
            switch p {
            case "priority": return (lm.localized("haiyou_priority", fallback: "优先资助 (≥85)"), .green)
            case "approved": return (lm.localized("haiyou_approved", fallback: "同意资助 (70–84)"), .orange)
            default: return (lm.localized("haiyou_rejected", fallback: "未达资助线 (<70)"), .red)
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
                cvText: cvText.isEmpty ? nil : cvText,
                returnPlanText: returnPlanText.isEmpty ? nil : returnPlanText,
                representativePapers: repPapers.filter { !$0.title.isEmpty },
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

// MARK: - Input sheet

private struct HaiyouInputSheet: View {
    @Binding var cvText: String
    @Binding var returnPlanText: String
    @Binding var repPapers: [RepresentativePaperInput]
    @Environment(\.dismiss) private var dismiss
    private let lm = LocalizationManager.shared

    var body: some View {
        NavigationView {
            Form {
                Section(lm.localized("haiyou_cv", fallback: "教育与工作经历（维度1）")) {
                    TextEditor(text: $cvText)
                        .frame(minHeight: 110)
                    Text(lm.localized("haiyou_cv_hint", fallback: "粘贴教育经历、博士后/工作单位、师承、重要项目等。"))
                        .font(.caption2).foregroundColor(.secondary)
                }
                Section(lm.localized("haiyou_plan", fallback: "回国设想与依托单位支持（维度5）")) {
                    TextEditor(text: $returnPlanText)
                        .frame(minHeight: 110)
                    Text(lm.localized("haiyou_plan_hint", fallback: "拟解决的关键科学问题、工作计划、依托单位的量化支持（实验室面积/设备/经费/团队）。"))
                        .font(.caption2).foregroundColor(.secondary)
                }
                Section(lm.localized("haiyou_reppapers", fallback: "代表作（维度2，最多5篇）")) {
                    ForEach($repPapers) { $p in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(lm.localized("haiyou_paper_title", fallback: "论文标题"), text: $p.title)
                            HStack {
                                TextField(lm.localized("haiyou_paper_journal", fallback: "期刊"), text: optStr($p.journal))
                                TextField("IF", text: optDouble($p.impactFactor))
                                    .keyboardType(.decimalPad)
                                    .frame(width: 60)
                            }
                            HStack {
                                TextField(lm.localized("haiyou_paper_role", fallback: "署名(如:唯一一作)"), text: optStr($p.authorRole))
                                TextField(lm.localized("haiyou_paper_cites", fallback: "他引"), text: optInt($p.citationCount))
                                    .keyboardType(.numberPad)
                                    .frame(width: 70)
                            }
                            Toggle(lm.localized("haiyou_paper_esi", fallback: "ESI 高被引"), isOn: Binding(
                                get: { p.esiHighlyCited ?? false }, set: { p.esiHighlyCited = $0 }
                            ))
                            .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { repPapers.remove(atOffsets: $0) }
                    if repPapers.count < 5 {
                        Button {
                            repPapers.append(RepresentativePaperInput())
                        } label: {
                            Label(lm.localized("haiyou_add_paper", fallback: "添加代表作"), systemImage: "plus.circle")
                        }
                    }
                }
            }
            .liquidGlassCanvas()
            .navigationTitle(lm.localized("haiyou_inputs_title", fallback: "补充材料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lm.localized("done", fallback: "完成")) { dismiss() }
                }
            }
        }
    }

    private func optStr(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func optDouble(_ b: Binding<Double?>) -> Binding<String> {
        Binding(
            get: { b.wrappedValue.map { String($0) } ?? "" },
            set: { b.wrappedValue = Double($0) }
        )
    }

    private func optInt(_ b: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { b.wrappedValue.map { String($0) } ?? "" },
            set: { b.wrappedValue = Int($0) }
        )
    }
}
