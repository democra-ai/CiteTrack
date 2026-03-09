import SwiftUI
import Charts

// MARK: - Main Charts View
struct ChartsContentView: View {
    @StateObject private var viewModel = ChartsViewModel()

    var body: some View {
        ZStack {
            backgroundGradient

            if viewModel.scholars.isEmpty {
                emptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                VStack(spacing: 0) {
                    ChartsToolbar(viewModel: viewModel)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                        .padding(.bottom, 14)

                    Divider()
                        .opacity(0.3)

                    HStack(spacing: 20) {
                        VStack(spacing: 16) {
                            DashboardStripView(viewModel: viewModel)
                            CitationChartView(viewModel: viewModel)
                        }

                        InsightSidebarView(viewModel: viewModel)
                            .frame(width: 220)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scholarsDataUpdated)) { _ in
            viewModel.reload()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.97)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.12), .blue.opacity(0.03)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 52
                        )
                    )
                    .frame(width: 104, height: 104)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(.blue.opacity(0.55))
            }

            VStack(spacing: 8) {
                Text(L("no_scholars_title"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L("no_scholars_message"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Model
class ChartsViewModel: ObservableObject {
    @Published var scholars: [Scholar] = []
    @Published var currentScholar: Scholar?
    @Published var timeRange: TimeRange = .lastMonth
    @Published var chartType: ChartType = .line
    @Published var theme: ChartTheme = .academic
    @Published var chartData: ChartData?
    @Published var isLoading = false
    @Published var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var customEndDate = Date()

    private let chartDataService = ChartDataService.shared
    private let historyManager = CitationHistoryManager.shared

    init() {
        reload()
    }

    func reload() {
        scholars = PreferencesManager.shared.scholars
        if currentScholar == nil || !scholars.contains(where: { $0.id == currentScholar?.id }) {
            currentScholar = scholars.first
        }
        loadChartData()
    }

    func selectScholar(_ scholar: Scholar) {
        guard scholar.id != currentScholar?.id else { return }
        currentScholar = scholar
        loadChartData()
    }

    func selectTimeRange(_ range: TimeRange) {
        if range == .custom { return }
        timeRange = range
        loadChartData()
    }

    func applyCustomRange(start: Date, end: Date) {
        customStartDate = min(start, end)
        customEndDate = max(start, end)
        timeRange = .custom
        loadChartData()
    }

    func refresh() {
        guard !isLoading else { return }
        loadChartData()
    }

    func loadChartData() {
        guard let scholar = currentScholar else {
            chartData = nil
            return
        }

        isLoading = true

        let completion: (Result<[CitationHistory], Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                switch result {
                case .success(let history):
                    self.processChartData(history, for: scholar)
                case .failure:
                    self.chartData = nil
                }
            }
        }

        if timeRange == .custom {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: customEndDate)) ?? customEndDate
            historyManager.getHistory(for: scholar.id, from: start, to: end, completion: completion)
        } else {
            historyManager.getHistory(for: scholar.id, in: timeRange, completion: completion)
        }
    }

    private func processChartData(_ history: [CitationHistory], for scholar: Scholar) {
        let config = ChartConfiguration(
            timeRange: timeRange,
            chartType: mappedChartType,
            showTrendLine: chartType != .bar && chartType != .scatter,
            showDataPoints: chartType != .area,
            showGrid: true,
            smoothLines: chartType == .smoothLine,
            colorScheme: colorScheme
        )
        chartData = chartDataService.prepareChartData(from: history, configuration: config, scholarName: scholar.name)
    }

    private var mappedChartType: ChartConfiguration.ChartType {
        switch chartType {
        case .bar: return .bar
        case .area: return .area
        default: return .line
        }
    }

    private var colorScheme: ChartConfiguration.ColorScheme {
        switch theme {
        case .academic: return .blue
        case .nature: return .green
        case .warm: return .orange
        case .mono, .auto: return .system
        }
    }

    func exportData() {
        guard let scholar = currentScholar else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText, .json]
        savePanel.nameFieldStringValue = "citations-\(scholar.id)"

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self = self else { return }

            let completion: (Result<[CitationHistory], Error>) -> Void = { result in
                switch result {
                case .success(let history):
                    do {
                        let data: Data
                        if url.pathExtension.lowercased() == "json" {
                            data = try JSONEncoder().encode(history)
                        } else {
                            var csv = "Date,Citations,Scholar\n"
                            for entry in history {
                                csv += "\(entry.timestamp),\(entry.citationCount),\(scholar.name)\n"
                            }
                            data = csv.data(using: .utf8) ?? Data()
                        }
                        try data.write(to: url)
                    } catch {
                        print("Export error: \(error)")
                    }
                case .failure(let error):
                    print("Export error: \(error)")
                }
            }

            if self.timeRange == .custom {
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: self.customStartDate)
                let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: self.customEndDate)) ?? self.customEndDate
                self.historyManager.getHistory(for: scholar.id, from: start, to: end, completion: completion)
            } else {
                self.historyManager.getHistory(for: scholar.id, in: self.timeRange, completion: completion)
            }
        }
    }
}

// MARK: - Toolbar
struct ChartsToolbar: View {
    @ObservedObject var viewModel: ChartsViewModel
    @State private var showCustomRange = false
    @State private var isHoveringRefresh = false
    @State private var isHoveringExport = false

    var body: some View {
        HStack(spacing: 14) {
            scholarPicker
            Spacer()
            timeRangePills
            Spacer()
            chartTypePicker
            actionButtons
        }
    }

    private var scholarPicker: some View {
        Menu {
            ForEach(viewModel.scholars, id: \.id) { scholar in
                Button(action: { viewModel.selectScholar(scholar) }) {
                    HStack {
                        Text(scholar.name.isEmpty ? "Scholar \(scholar.id.prefix(8))" : scholar.name)
                        if scholar.id == viewModel.currentScholar?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 26, height: 26)
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("SCHOLAR")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    Text(viewModel.currentScholar.map {
                        $0.name.isEmpty ? "Scholar \($0.id.prefix(8))" : $0.name
                    } ?? "Select")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var timeRangePills: some View {
        HStack(spacing: 2) {
            ForEach(TimeRange.allCases.filter { $0 != .custom }, id: \.self) { range in
                TimeRangePill(
                    label: shortLabel(for: range),
                    isSelected: viewModel.timeRange == range,
                    action: { viewModel.selectTimeRange(range) }
                )
            }

            Button(action: { showCustomRange = true }) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(viewModel.timeRange == .custom ? .white : .secondary)
                    .frame(width: 28, height: 24)
                    .background(
                        viewModel.timeRange == .custom
                        ? AnyShapeStyle(Color.blue)
                        : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
            }
            .buttonStyle(.plain)
            .help(L("time_range_custom"))
        }
        .padding(3)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showCustomRange) {
            CustomRangeSheet(
                startDate: $viewModel.customStartDate,
                endDate: $viewModel.customEndDate,
                onApply: {
                    viewModel.applyCustomRange(start: viewModel.customStartDate, end: viewModel.customEndDate)
                    showCustomRange = false
                },
                onCancel: { showCustomRange = false }
            )
        }
    }

    private var chartTypePicker: some View {
        HStack(spacing: 1) {
            ForEach(ChartType.allCases, id: \.self) { type in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.chartType = type
                        viewModel.loadChartData()
                    }
                }) {
                    Image(systemName: chartTypeIcon(type))
                        .font(.system(size: 12))
                        .foregroundStyle(viewModel.chartType == type ? .blue : .secondary)
                        .frame(width: 30, height: 24)
                        .background(
                            viewModel.chartType == type
                            ? Color.blue.opacity(0.12)
                            : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
                .buttonStyle(.plain)
                .help(type.displayName)
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            }

            Button(action: viewModel.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHoveringRefresh ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        isHoveringRefresh ? Color.primary.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .help(L("button_update"))
            .onHover { isHoveringRefresh = $0 }

            Button(action: viewModel.exportData) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHoveringExport ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        isHoveringExport ? Color.primary.opacity(0.06) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentScholar == nil)
            .help(L("export_to_device"))
            .onHover { isHoveringExport = $0 }
        }
    }

    private func shortLabel(for range: TimeRange) -> String {
        switch range {
        case .lastWeek: return "1W"
        case .lastMonth: return "1M"
        case .lastQuarter: return "3M"
        case .lastYear: return "1Y"
        case .custom: return ""
        }
    }

    private func chartTypeIcon(_ type: ChartType) -> String {
        switch type {
        case .line: return "chart.xyaxis.line"
        case .smoothLine: return "point.topleft.down.to.point.bottomright.curvepath"
        case .area: return "chart.line.uptrend.xyaxis"
        case .bar: return "chart.bar"
        case .scatter: return "circle.dotted"
        }
    }
}

// MARK: - Time Range Pill
struct TimeRangePill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : (isHovering ? .primary : .secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule().fill(Color.blue)
                            .shadow(color: .blue.opacity(0.3), radius: 4, y: 1)
                    } else if isHovering {
                        Capsule().fill(Color.primary.opacity(0.06))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}

// MARK: - Custom Range Sheet
struct CustomRangeSheet: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    var onApply: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("time_range_custom_title"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("time_range_custom_message"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("label_start_date").uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.quaternary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("label_end_date").uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(L("button_cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L("button_apply"), action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}

// MARK: - Dashboard Stats Strip
struct DashboardStripView: View {
    @ObservedObject var viewModel: ChartsViewModel

    var body: some View {
        HStack(spacing: 12) {
            if let data = viewModel.chartData, let scholar = viewModel.currentScholar {
                let stats = data.statistics

                StatCard(
                    label: L("total_citations"),
                    value: "\((scholar.citations ?? 0).formatted())",
                    icon: "quote.bubble.fill",
                    color: .blue,
                    badge: nil
                )

                StatCard(
                    label: L("monthly_change"),
                    value: formatChange(stats.totalChange),
                    icon: stats.totalChange >= 0 ? "arrow.up.right" : "arrow.down.right",
                    color: stats.totalChange >= 0 ? .green : .red,
                    badge: String(format: "%+.1f%%", stats.growthRate)
                )

                StatCard(
                    label: L("growth_rate"),
                    value: String(format: "%.1f%%", stats.growthRate),
                    icon: "percent",
                    color: stats.growthRate >= 0 ? .green : .orange,
                    badge: nil
                )

                StatCard(
                    label: L("trend_label"),
                    value: stats.trend.displayName,
                    icon: trendIcon(stats.trend),
                    color: Color(nsColor: stats.trend.color),
                    badge: nil
                )
            } else {
                ForEach(0..<4, id: \.self) { _ in
                    StatCard(label: "--", value: "--", icon: "minus", color: .gray, badge: nil)
                }
            }
        }
    }

    private func formatChange(_ change: Int) -> String {
        change >= 0 ? "+\(change)" : "\(change)"
    }

    private func trendIcon(_ trend: CitationTrend) -> String {
        switch trend {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    let badge: String?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(color.opacity(isHovering ? 0.15 : 0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)

                HStack(spacing: 5) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.1), in: Capsule())
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovering ? 0.06 : 0.03), radius: isHovering ? 8 : 4, y: isHovering ? 3 : 1)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovering)
    }
}

// MARK: - Insight Sidebar
struct InsightSidebarView: View {
    @ObservedObject var viewModel: ChartsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INSIGHTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(1.2)
                Spacer()

                Menu {
                    ForEach(ChartTheme.allCases, id: \.self) { theme in
                        Button(action: {
                            viewModel.theme = theme
                            viewModel.loadChartData()
                        }) {
                            HStack {
                                Text(theme.displayName)
                                if theme == viewModel.theme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(nsColor: viewModel.theme.colors.primary))
                            .frame(width: 7, height: 7)
                        Text(viewModel.theme.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)
                .opacity(0.5)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if let data = viewModel.chartData {
                        ForEach(Array(data.insights.enumerated()), id: \.offset) { _, insight in
                            SwiftUIInsightCard(insight: insight, theme: viewModel.theme)
                        }

                        if data.insights.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "lightbulb")
                                    .font(.system(size: 20, weight: .thin))
                                    .foregroundStyle(.quaternary)
                                Text("More data needed for insights")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }

                        if let stats = viewModel.chartData?.statistics {
                            Divider()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .opacity(0.5)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("DETAILS")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.quaternary)
                                    .tracking(1.0)

                                DetailRow(label: "Data Points", value: "\(stats.totalDataPoints)")
                                if let range = stats.valueRange {
                                    DetailRow(label: "Range", value: "\(range.min) - \(range.max)")
                                }
                                DetailRow(label: "Avg. Change", value: String(format: "%.1f", stats.averageChange))
                                DetailRow(label: "Volatility", value: String(format: "%.1f", stats.volatility))
                            }
                            .padding(.horizontal, 4)
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 24, weight: .ultraLight))
                                .foregroundStyle(.quaternary)
                            Text("Select a scholar to see insights")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Insight Card (SwiftUI)
struct SwiftUIInsightCard: View {
    let insight: ChartInsight
    let theme: ChartTheme
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(insightEmoji)
                        .font(.system(size: 11))
                    Text(insight.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(insight.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? accentColor.opacity(0.04) : Color.clear)
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var accentColor: Color {
        switch insight.type {
        case .positive: return Color(nsColor: theme.colors.success)
        case .negative: return Color(nsColor: theme.colors.error)
        case .warning: return Color(nsColor: theme.colors.warning)
        case .neutral: return Color(nsColor: theme.colors.textSecondary)
        }
    }

    private var insightEmoji: String {
        switch insight.type {
        case .positive: return "+"
        case .negative: return "-"
        case .warning: return "!"
        case .neutral: return "~"
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Citation Chart
struct CitationChartView: View {
    @ObservedObject var viewModel: ChartsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = viewModel.chartData {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.title)
                            .font(.system(size: 15, weight: .semibold))
                        if let subtitle = data.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            if let data = viewModel.chartData, !data.isEmpty {
                chartContent(data)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text(L("no_data_available"))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }

    private func yAxisDomain(for data: ChartData) -> ClosedRange<Int> {
        let values = data.points.map { $0.value }
        guard let minVal = values.min(), let maxVal = values.max() else {
            return 0...100
        }
        if minVal == maxVal {
            let center = minVal
            let pad = max(center / 20, 10)
            return (center - pad)...(center + pad)
        }
        let spread = maxVal - minVal
        let padding = max(spread / 4, 5)
        if viewModel.chartType == .bar && minVal < spread * 2 {
            return 0...(maxVal + padding)
        }
        return max(0, minVal - padding)...(maxVal + padding)
    }

    @ViewBuilder
    private func chartContent(_ data: ChartData) -> some View {
        let themeColors = viewModel.theme.colors

        Chart {
            ForEach(Array(data.points.enumerated()), id: \.offset) { _, point in
                switch viewModel.chartType {
                case .line, .smoothLine:
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Citations", point.value)
                    )
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Citations", point.value)
                    )
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .symbolSize(40)
                    .annotation(position: .overlay) {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .frame(width: 8, height: 8)
                    }

                case .area:
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Citations", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemBlue).opacity(0.3),
                                Color(nsColor: .systemBlue).opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Citations", point.value)
                    )
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
                    .interpolationMethod(.catmullRom)

                case .bar:
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Citations", point.value)
                    )
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .cornerRadius(3)

                case .scatter:
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Citations", point.value)
                    )
                    .foregroundStyle(Color(nsColor: .systemBlue).opacity(0.7))
                    .symbolSize(50)
                }
            }

            if let trendLine = data.trendLine, viewModel.chartType != .bar && viewModel.chartType != .scatter {
                if let firstPoint = data.points.first, let lastPoint = data.points.last {
                    let startY = trendLine.slope * 0 + trendLine.intercept
                    let endY = trendLine.slope * Double(data.points.count - 1) + trendLine.intercept

                    RuleMark(
                        xStart: .value("Start", firstPoint.date),
                        xEnd: .value("End", lastPoint.date),
                        y: .value("Trend", (startY + endY) / 2)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .foregroundStyle(Color.red.opacity(0.7))
                }
            }
        }
        .chartYScale(domain: yAxisDomain(for: data))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(.quaternary)
                AxisValueLabel()
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(.quaternary)
                AxisValueLabel()
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .border(Color.primary.opacity(0.05), width: 0.5)
        }
    }
}
