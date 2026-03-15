import Cocoa
import CoreGraphics

// MARK: - Chart View Delegate
protocol ChartViewDelegate: AnyObject {
    func chartView(_ chartView: ChartView, didSelectPoint point: ChartDataPoint)
    func chartView(_ chartView: ChartView, didHoverPoint point: ChartDataPoint?)
}

// MARK: - Chart View
// Design: Clean chart with desaturated grid, refined data visualization
// Off-white background, subtle axis labels, tinted data lines
class ChartView: NSView {

    // MARK: - Properties

    weak var delegate: ChartViewDelegate?

    var chartData: ChartData? {
        didSet {
            needsDisplay = true
            updateTrackingAreas()
        }
    }

    var configuration: ChartConfiguration = .default {
        didSet {
            needsDisplay = true
        }
    }

    private var hoveredPoint: ChartDataPoint?
    private var selectedPoint: ChartDataPoint?
    private var tooltipWindow: NSWindow?
    private var tooltipUpdateTimer: Timer?

    // Chart dimensions — generous margins for breathing room
    private let margins = NSEdgeInsets(top: 48, left: 64, bottom: 56, right: 48)
    private var chartRect: NSRect {
        return NSRect(
            x: margins.left,
            y: margins.bottom,
            width: bounds.width - margins.left - margins.right,
            height: bounds.height - margins.top - margins.bottom
        )
    }

    private func xPosition(for index: Int, totalPoints: Int, in rect: NSRect) -> CGFloat {
        guard totalPoints > 1 else {
            return rect.minX + rect.width / 2
        }

        let clampedIndex = min(max(index, 0), totalPoints - 1)
        let step = rect.width / CGFloat(totalPoints - 1)
        return rect.minX + step * CGFloat(clampedIndex)
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        // Off-white background
        layer?.backgroundColor = NSColor(hex: "#FAFAF8").cgColor
        layer?.cornerRadius = DesignSpacing.cardCornerRadius
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(hex: "#D8D6D0").withAlphaComponent(0.5).cgColor

        // Tinted shadow
        layer?.shadowColor = NSColor(hex: "#3B6B9A").withAlphaComponent(0.1).cgColor
        layer?.shadowOpacity = DesignSpacing.cardShadowOpacity
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        layer?.shadowRadius = DesignSpacing.cardShadowRadius

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    deinit {
        tooltipUpdateTimer?.invalidate()
        tooltipUpdateTimer = nil
        if let tooltip = tooltipWindow {
            tooltip.orderOut(nil)
            tooltipWindow = nil
        }
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        delegate = nil
        chartData = nil
        hoveredPoint = nil
        selectedPoint = nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw rounded-rect background
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: DesignSpacing.cardCornerRadius, cornerHeight: DesignSpacing.cardCornerRadius, transform: nil)
        context.addPath(bgPath)
        context.setFillColor(NSColor(hex: "#FAFAF8").cgColor)
        context.fillPath()

        guard let data = chartData, !data.isEmpty else {
            drawEmptyState(in: context)
            return
        }

        if configuration.showGrid {
            drawGrid(in: context, data: data)
        }

        drawAxes(in: context, data: data)
        drawAxisLabels(in: context, data: data)
        drawTitle(in: context, data: data)

        switch configuration.chartType {
        case .line:
            drawLineChart(in: context, data: data)
        case .bar:
            drawBarChart(in: context, data: data)
        case .area:
            drawAreaChart(in: context, data: data)
        }

        if configuration.showTrendLine, let trendLine = data.trendLine {
            drawTrendLine(in: context, trendLine: trendLine, data: data)
        }

        if configuration.showDataPoints {
            drawDataPoints(in: context, data: data)
        }

        if let hoveredPoint = hoveredPoint {
            drawPointHighlight(in: context, point: hoveredPoint, data: data)
        }
    }

    // MARK: - Empty State
    // Design: Centered, clean, with muted text
    private func drawEmptyState(in context: CGContext) {
        let message = "No citation data available"
        let subtitle = "Add scholars and refresh data to see charts"

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor(hex: "#8E8E93")
        ]

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(hex: "#AEAEB2")
        ]

        let titleString = NSAttributedString(string: message, attributes: titleAttributes)
        let subtitleString = NSAttributedString(string: subtitle, attributes: subtitleAttributes)

        let titleSize = titleString.size()
        let subtitleSize = subtitleString.size()

        let totalHeight = titleSize.height + 6 + subtitleSize.height
        let startY = (bounds.height - totalHeight) / 2

        let titleRect = NSRect(
            x: (bounds.width - titleSize.width) / 2,
            y: startY + subtitleSize.height + 6,
            width: titleSize.width,
            height: titleSize.height
        )

        let subtitleRect = NSRect(
            x: (bounds.width - subtitleSize.width) / 2,
            y: startY,
            width: subtitleSize.width,
            height: subtitleSize.height
        )

        titleString.draw(in: titleRect)
        subtitleString.draw(in: subtitleRect)
    }

    // MARK: - Grid Drawing
    // Design: Very subtle dashed grid — barely visible, not competing with data
    private func drawGrid(in context: CGContext, data: ChartData) {
        context.setStrokeColor(NSColor(hex: "#E5E3DF").withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [4, 4])

        let rect = chartRect
        let gridLines = 5

        // Horizontal grid lines only — cleaner
        for i in 1..<gridLines {
            let y = rect.minY + (rect.height / CGFloat(gridLines)) * CGFloat(i)
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    // MARK: - Axes Drawing
    // Design: Single pixel, muted color — not bold black
    private func drawAxes(in context: CGContext, data: ChartData) {
        context.setStrokeColor(NSColor(hex: "#D8D6D0").cgColor)
        context.setLineWidth(0.5)

        let rect = chartRect

        // X-axis only — bottom line
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        context.strokePath()
    }

    // MARK: - Label Drawing
    // Design: Small, muted, monospaced numbers for Y-axis
    private func drawAxisLabels(in context: CGContext, data: ChartData) {
        let rect = chartRect
        let yRange = data.yAxisRange

        // Y-axis labels — monospaced for alignment
        let yLabelCount = 5
        let yStep = (yRange.max - yRange.min) / Double(yLabelCount)

        for i in 0...yLabelCount {
            let value = yRange.min + Double(i) * yStep
            let y = rect.minY + (rect.height / CGFloat(yLabelCount)) * CGFloat(i)

            let labelText = String(format: "%.0f", value)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor(hex: "#8E8E93")
            ]

            let attributedString = NSAttributedString(string: labelText, attributes: attributes)
            let size = attributedString.size()
            let labelRect = NSRect(
                x: rect.minX - size.width - 10,
                y: y - size.height / 2,
                width: size.width,
                height: size.height
            )

            attributedString.draw(in: labelRect)
        }

        // X-axis labels
        let xLabels = data.xAxisLabels
        if !xLabels.isEmpty && !data.points.isEmpty {
            let maxLabels = min(8, xLabels.count)
            let step = max(1, xLabels.count / maxLabels)

            for i in stride(from: 0, to: xLabels.count, by: step) {
                let x = xPosition(for: i, totalPoints: data.points.count, in: rect)
                let label = xLabels[i]

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor(hex: "#8E8E93")
                ]

                let attributedString = NSAttributedString(string: label, attributes: attributes)
                let size = attributedString.size()
                let labelRect = NSRect(
                    x: x - size.width / 2,
                    y: rect.minY - size.height - 10,
                    width: size.width,
                    height: size.height
                )

                attributedString.draw(in: labelRect)
            }
        }
    }

    // MARK: - Title Drawing
    // Design: Left-aligned title, not centered — more professional
    private func drawTitle(in context: CGContext, data: ChartData) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor(hex: "#1C1C1E")
        ]

        let titleString = NSAttributedString(string: data.title, attributes: titleAttributes)
        let titleRect = NSRect(
            x: margins.left,
            y: bounds.height - margins.top + 12,
            width: bounds.width - margins.left - margins.right,
            height: 20
        )

        titleString.draw(in: titleRect)

        if let subtitle = data.subtitle {
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor(hex: "#6E6E73")
            ]

            let subtitleString = NSAttributedString(string: subtitle, attributes: subtitleAttributes)
            let subtitleRect = NSRect(
                x: margins.left,
                y: titleRect.minY - 16,
                width: bounds.width - margins.left - margins.right,
                height: 14
            )

            subtitleString.draw(in: subtitleRect)
        }
    }

    // MARK: - Chart Type Drawing
    // Design: 2px line with desaturated primary color, smooth curves

    private func drawLineChart(in context: CGContext, data: ChartData) {
        guard !data.points.isEmpty else { return }

        let rect = chartRect
        let yRange = data.yAxisRange
        let points = data.points

        context.setStrokeColor(configuration.colorScheme.primaryColor.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if points.count == 1 {
            let point = points[0]
            let x = rect.minX + rect.width / 2
            let y = rect.minY + (rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min)))

            context.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: y))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: y))
            context.strokePath()

            context.setFillColor(configuration.colorScheme.primaryColor.cgColor)
            let pointRect = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
            context.fillEllipse(in: pointRect)
            return
        }

        let path = CGMutablePath()

        for (index, point) in points.enumerated() {
            let x = xPosition(for: index, totalPoints: points.count, in: rect)
            let y = rect.minY + (rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min)))

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                if configuration.smoothLines {
                    let previousIndex = index - 1
                    let prevX = xPosition(for: previousIndex, totalPoints: points.count, in: rect)
                    let prevY = rect.minY + (rect.height * CGFloat((points[previousIndex].y - yRange.min) / (yRange.max - yRange.min)))

                    let controlPoint1 = CGPoint(x: prevX + (x - prevX) * 0.5, y: prevY)
                    let controlPoint2 = CGPoint(x: prevX + (x - prevX) * 0.5, y: y)

                    path.addCurve(to: CGPoint(x: x, y: y), control1: controlPoint1, control2: controlPoint2)
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }

        context.addPath(path)
        context.strokePath()
    }

    private func drawBarChart(in context: CGContext, data: ChartData) {
        guard !data.points.isEmpty else { return }

        let rect = chartRect
        let yRange = data.yAxisRange
        let points = data.points

        if points.count == 1 {
            let point = points[0]
            let barWidth = min(rect.width * 0.3, 60)
            let x = rect.minX + (rect.width - barWidth) / 2
            let height = rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min))

            // Rounded top corners
            let barPath = CGPath(
                roundedRect: CGRect(x: x, y: rect.minY, width: barWidth, height: height),
                cornerWidth: 4, cornerHeight: 4, transform: nil
            )
            context.addPath(barPath)
            context.setFillColor(configuration.colorScheme.primaryColor.withAlphaComponent(0.75).cgColor)
            context.fillPath()
            return
        }

        let barWidth = rect.width / CGFloat(points.count) * 0.7
        let barSpacing = rect.width / CGFloat(points.count) * 0.3

        for (index, point) in points.enumerated() {
            let x = rect.minX + (rect.width / CGFloat(points.count)) * CGFloat(index) + barSpacing / 2
            let height = rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min))

            let barPath = CGPath(
                roundedRect: CGRect(x: x, y: rect.minY, width: barWidth, height: height),
                cornerWidth: 3, cornerHeight: 3, transform: nil
            )
            context.addPath(barPath)
            context.setFillColor(configuration.colorScheme.primaryColor.withAlphaComponent(0.7).cgColor)
            context.fillPath()
        }
    }

    private func drawAreaChart(in context: CGContext, data: ChartData) {
        guard !data.points.isEmpty else { return }

        let rect = chartRect
        let yRange = data.yAxisRange
        let points = data.points

        // Gradient fill — very subtle
        context.setFillColor(configuration.colorScheme.primaryColor.withAlphaComponent(0.08).cgColor)

        if points.count == 1 {
            let point = points[0]
            let y = rect.minY + (rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min)))

            let areaWidth = rect.width * 0.6
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + (rect.width - areaWidth) / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + (rect.width - areaWidth) / 2, y: y))
            path.addLine(to: CGPoint(x: rect.minX + (rect.width + areaWidth) / 2, y: y))
            path.addLine(to: CGPoint(x: rect.minX + (rect.width + areaWidth) / 2, y: rect.minY))
            path.closeSubpath()

            context.addPath(path)
            context.fillPath()

            drawLineChart(in: context, data: data)
            return
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        for (index, point) in points.enumerated() {
            let x = xPosition(for: index, totalPoints: points.count, in: rect)
            let y = rect.minY + (rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min)))
            path.addLine(to: CGPoint(x: x, y: y))
        }

        let lastX = rect.minX + rect.width
        path.addLine(to: CGPoint(x: lastX, y: rect.minY))
        path.closeSubpath()

        context.addPath(path)
        context.fillPath()

        drawLineChart(in: context, data: data)
    }

    // MARK: - Trend Line Drawing
    // Design: Dashed, desaturated accent color
    private func drawTrendLine(in context: CGContext, trendLine: TrendLineData, data: ChartData) {
        let rect = chartRect
        let yRange = data.yAxisRange

        context.setStrokeColor(NSColor(hex: "#B84A3C").withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [6, 4])

        guard let startPoint = trendLine.points.first, let endPoint = trendLine.points.last else { return }

        let startX = rect.minX
        let startY = rect.minY + (rect.height * CGFloat((startPoint.y - yRange.min) / (yRange.max - yRange.min)))

        let endX = rect.maxX
        let endY = rect.minY + (rect.height * CGFloat((endPoint.y - yRange.min) / (yRange.max - yRange.min)))

        context.move(to: CGPoint(x: startX, y: startY))
        context.addLine(to: CGPoint(x: endX, y: endY))
        context.strokePath()

        context.setLineDash(phase: 0, lengths: [])
    }

    // MARK: - Data Points Drawing
    // Design: Small solid dots with white stroke for definition
    private func drawDataPoints(in context: CGContext, data: ChartData) {
        guard !data.points.isEmpty else { return }

        let rect = chartRect
        let yRange = data.yAxisRange
        let points = data.points

        for (index, point) in points.enumerated() {
            let x = xPosition(for: index, totalPoints: points.count, in: rect)
            let y = rect.minY + (rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min)))

            // White stroke ring
            context.setFillColor(NSColor(hex: "#FAFAF8").cgColor)
            context.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))

            // Colored inner dot
            context.setFillColor(configuration.colorScheme.primaryColor.cgColor)
            context.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
        }
    }

    // MARK: - Point Highlight Drawing
    // Design: Larger ring with crosshair line
    private func drawPointHighlight(in context: CGContext, point: ChartDataPoint, data: ChartData) {
        let rect = chartRect
        let yRange = data.yAxisRange

        guard let index = data.points.firstIndex(where: { $0.date == point.date }) else { return }

        let x = xPosition(for: index, totalPoints: data.points.count, in: rect)
        let y = rect.minY + (rect.height * CGFloat((point.y - yRange.min) / (yRange.max - yRange.min)))

        // Vertical crosshair — very subtle
        context.setStrokeColor(configuration.colorScheme.primaryColor.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.move(to: CGPoint(x: x, y: rect.minY))
        context.addLine(to: CGPoint(x: x, y: rect.maxY))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        // Outer glow ring
        context.setFillColor(configuration.colorScheme.primaryColor.withAlphaComponent(0.1).cgColor)
        context.fillEllipse(in: CGRect(x: x - 10, y: y - 10, width: 20, height: 20))

        // Inner dot
        context.setFillColor(NSColor(hex: "#FAFAF8").cgColor)
        context.fillEllipse(in: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
        context.setFillColor(configuration.colorScheme.primaryColor.cgColor)
        context.fillEllipse(in: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7))
    }

    // MARK: - Mouse Handling

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        tooltipUpdateTimer?.invalidate()
        tooltipUpdateTimer = nil

        let location = convert(event.locationInWindow, from: nil)

        guard window != nil, superview != nil, !isHidden, bounds.contains(location) else {
            if hoveredPoint != nil {
                hoveredPoint = nil
                needsDisplay = true
                hideTooltipImmediately()
                delegate?.chartView(self, didHoverPoint: nil)
            }
            return
        }

        let point = findNearestPoint(to: location)

        if point != hoveredPoint {
            hoveredPoint = point
            needsDisplay = true

            delegate?.chartView(self, didHoverPoint: point)

            if let point = point {
                if let currentWindow = self.window {
                    let currentLocation = NSEvent.mouseLocation
                    let windowLocation = currentWindow.convertFromScreen(NSRect(origin: currentLocation, size: .zero)).origin
                    let viewLocation = self.convert(windowLocation, from: nil)
                    self.showTooltipSafely(for: point, at: viewLocation)
                }
            } else {
                hideTooltipImmediately()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        tooltipUpdateTimer?.invalidate()
        tooltipUpdateTimer = nil

        hoveredPoint = nil
        needsDisplay = true
        hideTooltipImmediately()

        delegate?.chartView(self, didHoverPoint: nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard window != nil, superview != nil else { return }

        let location = convert(event.locationInWindow, from: nil)
        if let point = findNearestPoint(to: location) {
            selectedPoint = point
            delegate?.chartView(self, didSelectPoint: point)
        }
    }

    // MARK: - Point Finding

    private func findNearestPoint(to location: NSPoint) -> ChartDataPoint? {
        guard let data = chartData,
              !data.points.isEmpty else {
            return nil
        }

        let rect = chartRect

        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        guard rect.contains(location) else { return nil }

        let yRange = data.yAxisRange
        let points = data.points

        guard yRange.max > yRange.min,
              yRange.max.isFinite,
              yRange.min.isFinite else {
            return nil
        }

        var nearestPoint: ChartDataPoint?
        var nearestDistance: CGFloat = CGFloat.greatestFiniteMagnitude

        for (index, point) in points.enumerated() {
            guard point.y.isFinite else { continue }

            let x = xPosition(for: index, totalPoints: points.count, in: rect)

            let normalizedY = (point.y - yRange.min) / (yRange.max - yRange.min)
            let clampedY = max(0, min(1, normalizedY))
            let y = rect.minY + (rect.height * CGFloat(clampedY))

            guard x.isFinite, y.isFinite else { continue }

            let distance = sqrt(pow(location.x - x, 2) + pow(location.y - y, 2))

            guard distance.isFinite else { continue }

            if distance < nearestDistance && distance < 20 {
                nearestDistance = distance
                nearestPoint = point
            }
        }

        return nearestPoint
    }

    // MARK: - Tooltip
    // Design: Clean tooltip with rounded corners, subtle shadow, proper typography

    private func showTooltipSafely(for point: ChartDataPoint, at location: NSPoint) {
        hideTooltipImmediately()

        guard let window = window,
              !isHidden,
              window.isVisible else {
            return
        }

        let tooltipText = """
        \(point.label)
        \(point.value) citations
        """

        let tooltipView = TooltipView(text: tooltipText)
        let tooltipSize = tooltipView.intrinsicContentSize

        let windowLocation = convert(location, to: nil)
        let screenLocation = window.convertToScreen(NSRect(origin: windowLocation, size: .zero)).origin

        let windowFrame = window.frame
        var tooltipX = screenLocation.x + 12
        var tooltipY = screenLocation.y - tooltipSize.height - 8

        if tooltipX + tooltipSize.width > windowFrame.maxX - 8 {
            tooltipX = max(windowFrame.maxX - tooltipSize.width - 8, windowFrame.minX + 8)
        }
        if tooltipX < windowFrame.minX + 8 {
            tooltipX = windowFrame.minX + 8
        }
        if tooltipY + tooltipSize.height > windowFrame.maxY - 8 {
            tooltipY = windowFrame.maxY - tooltipSize.height - 8
        }
        if tooltipY < windowFrame.minY + 8 {
            tooltipY = windowFrame.minY + 8
        }

        let tooltipFrame = NSRect(
            x: tooltipX,
            y: tooltipY,
            width: tooltipSize.width,
            height: tooltipSize.height
        )

        let newTooltipWindow = NSWindow(
            contentRect: tooltipFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        newTooltipWindow.contentView = tooltipView
        newTooltipWindow.backgroundColor = NSColor.clear
        newTooltipWindow.isOpaque = false
        newTooltipWindow.level = .floating
        newTooltipWindow.hidesOnDeactivate = false
        newTooltipWindow.ignoresMouseEvents = true

        tooltipWindow = newTooltipWindow
        newTooltipWindow.orderFront(nil)
    }

    private func hideTooltipImmediately() {
        if let tooltip = tooltipWindow {
            tooltip.orderOut(nil)
            tooltipWindow = nil
        }
    }
}

// MARK: - Tooltip View
// Design: Off-white background, subtle border, refined typography

class TooltipView: NSView {
    private let text: String
    private let attributes: [NSAttributedString.Key: Any]

    init(text: String) {
        self.text = text
        self.attributes = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(hex: "#1C1C1E")
        ]
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        layer = nil
    }

    private func setupView() {
        guard Thread.isMainThread else {
            DispatchQueue.main.sync {
                setupView()
            }
            return
        }

        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#FAFAF8").withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(hex: "#D8D6D0").withAlphaComponent(0.6).cgColor

        // Subtle shadow
        layer?.shadowColor = NSColor(hex: "#1C1C1E").withAlphaComponent(0.1).cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowRadius = 8
    }

    override var intrinsicContentSize: NSSize {
        let sizeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]

        let attributedString = NSAttributedString(string: text, attributes: sizeAttributes)
        let size = attributedString.size()

        return NSSize(width: size.width + 24, height: size.height + 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = NSRect(
            x: 12,
            y: 8,
            width: bounds.width - 24,
            height: bounds.height - 16
        )

        attributedString.draw(in: textRect)
    }
}
