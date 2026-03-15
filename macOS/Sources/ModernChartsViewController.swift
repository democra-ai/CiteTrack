import Cocoa

// MARK: - Modern Charts View Controller
// Design: Clean layout with proper spacing rhythm
// Toolbar → Dashboard cards → Chart + Insight sidebar
class ModernChartsViewController: NSViewController {

    // MARK: - Modern UI Components
    private var modernToolbar: ModernToolbar!
    private var modernChartView: ModernChartView!
    private var dashboardView: DashboardView!
    private var insightPanel: InsightPanel!

    // MARK: - Data & State
    private var scholars: [Scholar] = []
    private var currentScholar: Scholar?
    private var currentTimeRange: TimeRange = .lastMonth
    private var currentChartType: ChartType = .line
    private var currentTheme: ChartTheme = .academic
    private var customStartDate: Date?
    private var customEndDate: Date?
    private var previousTimeRange: TimeRange?

    // Services
    private let chartDataService = ChartDataService()
    private let historyManager = CitationHistoryManager.shared

    // Animation & Interaction
    private var isDataLoading = false
    private var animationTimer: Timer?

    // Cleanup flag
    private var isCleanedUp = false

    // MARK: - Lifecycle
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 720))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(hex: "#F5F5F3").cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupModernUI()
        loadData()
        setupNotifications()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        animateViewAppearance()
    }

    deinit {
        isCleanedUp = true
        animationTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Modern UI Setup
    private func setupModernUI() {
        setupModernToolbar()
        setupModernChartView()
        setupDashboard()
        setupInsightPanel()
        setupLayout()
        setupTheme()
    }

    private func setupModernToolbar() {
        modernToolbar = ModernToolbar()
        modernToolbar.theme = currentTheme
        modernToolbar.translatesAutoresizingMaskIntoConstraints = false

        modernToolbar.onScholarChanged = { [weak self] scholar in
            self?.selectScholar(scholar)
        }

        modernToolbar.onTimeRangeChanged = { [weak self] timeRange in
            self?.selectTimeRange(timeRange)
        }

        modernToolbar.onChartTypeChanged = { [weak self] chartType in
            self?.selectChartType(chartType)
        }

        modernToolbar.onThemeChanged = { [weak self] theme in
            self?.applyTheme(theme)
        }

        modernToolbar.onRefresh = { [weak self] in
            self?.refreshData()
        }

        modernToolbar.onExport = { [weak self] in
            self?.exportData()
        }

        modernToolbar.onDataManagement = { [weak self] in
            self?.openDataManagement()
        }

        view.addSubview(modernToolbar)
    }

    private func setupModernChartView() {
        modernChartView = ModernChartView()
        modernChartView.theme = currentTheme
        modernChartView.chartType = currentChartType
        modernChartView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(modernChartView)
    }

    private func setupDashboard() {
        dashboardView = DashboardView()
        dashboardView.theme = currentTheme
        dashboardView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(dashboardView)
    }

    private func setupInsightPanel() {
        insightPanel = InsightPanel()
        insightPanel.theme = currentTheme
        insightPanel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(insightPanel)
    }

    private func setupLayout() {
        let edge = DesignSpacing.xl  // 24px edge padding
        let gap = DesignSpacing.md   // 16px between sections

        NSLayoutConstraint.activate([
            // Toolbar — flush to edges at top
            modernToolbar.topAnchor.constraint(equalTo: view.topAnchor),
            modernToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            modernToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Dashboard cards — below toolbar
            dashboardView.topAnchor.constraint(equalTo: modernToolbar.bottomAnchor, constant: edge),
            dashboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: edge),
            dashboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -edge),
            dashboardView.heightAnchor.constraint(equalToConstant: 110),

            // Chart view — main content area
            modernChartView.topAnchor.constraint(equalTo: dashboardView.bottomAnchor, constant: gap),
            modernChartView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: edge),
            modernChartView.trailingAnchor.constraint(equalTo: insightPanel.leadingAnchor, constant: -gap),
            modernChartView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -edge),

            // Insight panel — right sidebar
            insightPanel.topAnchor.constraint(equalTo: dashboardView.bottomAnchor, constant: gap),
            insightPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -edge),
            insightPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -edge),
            insightPanel.widthAnchor.constraint(equalToConstant: 200)
        ])
    }

    private func setupTheme() {
        applyTheme(currentTheme)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scholarsUpdated),
            name: .scholarsDataUpdated,
            object: nil
        )
    }

    // MARK: - Data Management
    private func loadData() {
        scholars = PreferencesManager.shared.scholars

        if let firstScholar = scholars.first {
            currentScholar = firstScholar
        }

        updateToolbarData()
        loadChartData()
    }

    private func updateToolbarData() {
        modernToolbar.updateScholarList(scholars, selectedScholar: currentScholar)
        modernToolbar.updateTimeRangeSelection(selectedRange: currentTimeRange, customLabel: customRangeDescription())
        modernToolbar.updateChartTypeSelection(currentChartType)
        modernToolbar.updateThemeSelection(currentTheme)
        modernToolbar.setRealTimeStatus(true)
    }

    private func loadChartData() {
        guard let scholar = currentScholar else {
            clearChartData()
            return
        }

        isDataLoading = true
        modernToolbar.showRefreshProgress()

        let completion: (Result<[CitationHistory], Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, !self.isCleanedUp else { return }

                self.isDataLoading = false
                self.modernToolbar.hideRefreshProgress()

                switch result {
                case .success(let history):
                    self.processChartData(history, for: scholar)
                case .failure(let error):
                    print("Failed to load chart data: \(error)")
                    self.showError("data_load_failed".localized, error.localizedDescription)
                }
            }
        }

        if currentTimeRange == .custom, let start = customStartDate, let end = customEndDate {
            let normalized = normalizedCustomRange(start: start, end: end)
            historyManager.getHistory(for: scholar.id, from: normalized.start, to: normalized.end, completion: completion)
        } else {
            historyManager.getHistory(for: scholar.id, in: currentTimeRange, completion: completion)
        }
    }

    private func processChartData(_ history: [CitationHistory], for scholar: Scholar) {
        let chartData = chartDataService.prepareChartData(
            from: history,
            configuration: makeChartConfiguration(),
            scholarName: scholar.name
        )

        modernChartView.chartData = chartData
        dashboardView.updateStatistics(chartData.statistics, scholar: scholar)
        insightPanel.updateInsights(chartData.insights)

        animateChartUpdate()
    }

    private func clearChartData() {
        modernChartView.chartData = nil
        dashboardView.clearStatistics()
        insightPanel.clearInsights()
    }

    // MARK: - User Actions
    private func selectScholar(_ scholar: Scholar) {
        guard scholar.id != currentScholar?.id else { return }

        currentScholar = scholar
        modernToolbar.updateScholarList(scholars, selectedScholar: scholar)
        loadChartData()
    }

    private func selectTimeRange(_ timeRange: TimeRange) {
        if timeRange == .custom {
            previousTimeRange = currentTimeRange
            presentCustomRangePicker()
            return
        }

        guard timeRange != currentTimeRange else { return }

        currentTimeRange = timeRange
        customStartDate = nil
        customEndDate = nil
        modernToolbar.updateTimeRangeSelection(selectedRange: currentTimeRange)
        loadChartData()
    }

    private func selectChartType(_ chartType: ChartType) {
        guard chartType != currentChartType else { return }

        currentChartType = chartType
        modernChartView.chartType = chartType
        modernToolbar.updateChartTypeSelection(chartType)
    }

    private func applyTheme(_ theme: ChartTheme) {
        guard theme != currentTheme else { return }

        currentTheme = theme

        modernToolbar.theme = theme
        modernToolbar.updateThemeSelection(theme)
        modernChartView.theme = theme
        dashboardView.theme = theme
        insightPanel.theme = theme

        // Animate background color transition
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            view.layer?.backgroundColor = theme.colors.background.cgColor
        })
    }

    private func refreshData() {
        guard !isDataLoading else { return }
        loadChartData()
    }

    private func exportData() {
        guard let scholar = currentScholar else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText, .json]
        savePanel.nameFieldStringValue = "citations-\(scholar.id)-\(Date().formatted())"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            self.performExport(to: url, scholar: scholar)
        }
    }

    private func performExport(to url: URL, scholar: Scholar) {
        let completion: (Result<[CitationHistory], Error>) -> Void = { result in
            switch result {
            case .success(let history):
                self.exportHistory(history, to: url, scholar: scholar)
            case .failure(let error):
                DispatchQueue.main.async {
                    self.showError("export_failed".localized, error.localizedDescription)
                }
            }
        }

        if currentTimeRange == .custom, let start = customStartDate, let end = customEndDate {
            let normalized = normalizedCustomRange(start: start, end: end)
            historyManager.getHistory(for: scholar.id, from: normalized.start, to: normalized.end, completion: completion)
        } else {
            historyManager.getHistory(for: scholar.id, in: currentTimeRange, completion: completion)
        }
    }

    private func exportHistory(_ history: [CitationHistory], to url: URL, scholar: Scholar) {
        do {
            let data: Data

            if url.pathExtension.lowercased() == "json" {
                data = try JSONEncoder().encode(history)
            } else {
                var csvContent = "Date,Citations,Scholar\n"
                for entry in history {
                    csvContent += "\(entry.date),\(entry.citationCount),\(scholar.name)\n"
                }
                data = csvContent.data(using: .utf8) ?? Data()
            }

            try data.write(to: url)

            DispatchQueue.main.async {
                self.showExportSuccessMessage(url: url)
            }
        } catch {
            DispatchQueue.main.async {
                self.showError(L("export_failed"), error.localizedDescription)
            }
        }
    }

    private func openDataManagement() {
        let dataRepairVC = DataRepairViewController()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = L("window_data_management")
        window.contentViewController = dataRepairVC
        window.center()
        window.minSize = NSSize(width: 800, height: 500)
        window.isReleasedWhenClosed = false

        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Custom Time Range Handling

    private func presentCustomRangePicker() {
        let alert = NSAlert()
        alert.messageText = L("time_range_custom_title")
        alert.informativeText = L("time_range_custom_message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("button_apply"))
        alert.addButton(withTitle: L("button_cancel"))

        let defaults = defaultCustomRange()
        let startPicker = makeDatePicker(initial: customStartDate ?? defaults.start)
        let endPicker = makeDatePicker(initial: customEndDate ?? defaults.end)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = DesignSpacing.sm
        stack.alignment = .centerY

        let startLabel = NSTextField(labelWithString: L("label_start_date"))
        startLabel.font = NSFont.systemFont(ofSize: 12)
        let endLabel = NSTextField(labelWithString: L("label_end_date"))
        endLabel.font = NSFont.systemFont(ofSize: 12)

        stack.addArrangedSubview(startLabel)
        stack.addArrangedSubview(startPicker)
        stack.addArrangedSubview(endLabel)
        stack.addArrangedSubview(endPicker)

        alert.accessoryView = stack

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            var startDate = startPicker.dateValue
            var endDate = endPicker.dateValue

            if startDate > endDate {
                swap(&startDate, &endDate)
            }

            customStartDate = startDate
            customEndDate = endDate
            currentTimeRange = .custom

            modernToolbar.updateTimeRangeSelection(
                selectedRange: .custom,
                customLabel: customRangeDescription(start: startDate, end: endDate)
            )

            loadChartData()
        } else if let previous = previousTimeRange {
            currentTimeRange = previous
            modernToolbar.updateTimeRangeSelection(selectedRange: previous, customLabel: customRangeDescription())
        }
        previousTimeRange = nil
    }

    private func makeDatePicker(initial: Date) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = initial
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return picker
    }

    private func defaultCustomRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .month, value: -1, to: end) ?? end
        return (start, end)
    }

    private func customRangeDescription(start: Date? = nil, end: Date? = nil) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        guard let startValue = start ?? customStartDate,
              let endValue = end ?? customEndDate else {
            return nil
        }

        return "\(formatter.string(from: startValue)) - \(formatter.string(from: endValue))"
    }

    private func normalizedCustomRange(start: Date, end: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: start)
        guard let normalizedEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end)) else {
            return (normalizedStart, end)
        }
        return (normalizedStart, normalizedEnd)
    }

    // MARK: - Chart Configuration Helpers

    private func makeChartConfiguration() -> ChartConfiguration {
        ChartConfiguration(
            timeRange: currentTimeRange,
            chartType: mappedChartType(for: currentChartType),
            showTrendLine: shouldShowTrendLine(for: currentChartType),
            showDataPoints: shouldShowDataPoints(for: currentChartType),
            showGrid: true,
            smoothLines: currentChartType == .smoothLine,
            colorScheme: colorScheme(for: currentTheme)
        )
    }

    private func mappedChartType(for chartType: ChartType) -> ChartConfiguration.ChartType {
        switch chartType {
        case .bar:
            return .bar
        case .area:
            return .area
        default:
            return .line
        }
    }

    private func shouldShowTrendLine(for chartType: ChartType) -> Bool {
        return false
    }

    private func shouldShowDataPoints(for chartType: ChartType) -> Bool {
        switch chartType {
        case .area:
            return false
        default:
            return true
        }
    }

    private func colorScheme(for theme: ChartTheme) -> ChartConfiguration.ColorScheme {
        switch theme {
        case .academic:
            return .blue
        case .nature:
            return .green
        case .warm:
            return .orange
        case .mono, .auto:
            return .system
        }
    }

    // MARK: - Animations
    // Design: Staggered reveal — each section fades in sequentially
    private func animateViewAppearance() {
        let components: [NSView?] = [modernToolbar, dashboardView, modernChartView, insightPanel]

        for (index, component) in components.enumerated() {
            component?.layer?.opacity = 0
            component?.layer?.transform = CATransform3DMakeTranslation(0, 12, 0)

            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.06) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                    context.allowsImplicitAnimation = true

                    component?.layer?.opacity = 1
                    component?.layer?.transform = CATransform3DIdentity
                }
            }
        }
    }

    private func animateChartUpdate() {
        modernChartView.layer?.removeAllAnimations()

        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.98
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = 0.2
        scaleAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)

        modernChartView.layer?.add(scaleAnimation, forKey: "chartUpdate")
    }

    // MARK: - Helper Methods
    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("button_ok"))
        alert.runModal()
    }

    private func showExportSuccessMessage(url: URL) {
        let alert = NSAlert()
        alert.messageText = L("export_success")
        alert.informativeText = url.lastPathComponent
        alert.addButton(withTitle: L("button_ok"))
        alert.addButton(withTitle: L("open_folder"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func scholarsUpdated() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isCleanedUp else { return }
            self.loadData()
        }
    }
}

// MARK: - Extension for NSView center property
extension NSView {
    var center: CGPoint {
        get {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        set {
            frame.origin = CGPoint(
                x: newValue.x - frame.width / 2,
                y: newValue.y - frame.height / 2
            )
        }
    }
}
