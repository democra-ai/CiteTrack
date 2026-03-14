import Foundation
import CoreGraphics
import Cocoa

// MARK: - Chart Insight Data Models
struct ChartInsight {
    let title: String
    let message: String
    let type: InsightType
    let icon: NSImage?
    let priority: InsightPriority
    
    static func generateInsights(from statistics: ChartStatistics) -> [ChartInsight] {
        var insights: [ChartInsight] = []
        
        // Growth insight
        if statistics.growthRate > 10 {
            insights.append(ChartInsight(
                title: "Strong Growth",
                message: "Your citations are growing at \(String(format: "%.1f", statistics.growthRate))% - excellent progress!",
                type: .positive,
                icon: nil, // Will use emoji in UI
                priority: .high
            ))
        } else if statistics.growthRate < -5 {
            insights.append(ChartInsight(
                title: "Citation Decline",
                message: "Citations decreased by \(String(format: "%.1f", abs(statistics.growthRate)))%. Consider promoting recent work.",
                type: .negative,
                icon: nil, // Will use emoji in UI
                priority: .high
            ))
        }
        
        // Data quality insight
        if statistics.totalDataPoints < 5 {
            insights.append(ChartInsight(
                title: "Limited Data",
                message: "Only \(statistics.totalDataPoints) data points available. More data will improve trend analysis.",
                type: .warning,
                icon: nil, // Will use emoji in UI
                priority: .medium
            ))
        }
        
        // Trend insight
        switch statistics.trend {
        case .increasing:
            insights.append(ChartInsight(
                title: "Upward Trend",
                message: "Your citation count shows a consistent upward trend. Keep up the great work!",
                type: .positive,
                icon: nil, // Will use emoji in UI
                priority: .medium
            ))
        case .stable:
            insights.append(ChartInsight(
                title: "Stable Citations",
                message: "Citation count is stable. Consider new publication strategies to boost growth.",
                type: .neutral,
                icon: nil, // Will use emoji in UI
                priority: .low
            ))
        default:
            break
        }
        
        return insights.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
}

enum InsightType {
    case positive
    case negative
    case neutral
    case warning
}

enum InsightPriority: Int {
    case low = 1
    case medium = 2
    case high = 3
}

// MARK: - Chart Data Models

struct ChartData {
    let points: [ChartDataPoint]
    let xAxisLabels: [String]
    let yAxisRange: (min: Double, max: Double)
    let title: String
    let subtitle: String?
    let trendLine: TrendLineData?
    let statistics: ChartStatistics
    let insights: [ChartInsight]
    
    var isEmpty: Bool {
        return points.isEmpty
    }
}

struct ChartDataPoint: Equatable {
    let x: Double
    let y: Double
    let date: Date
    let value: Int
    let label: String
    let metadata: [String: Any]
    
    init(x: Double, y: Double, date: Date, value: Int, label: String = "", metadata: [String: Any] = [:]) {
        self.x = x
        self.y = y
        self.date = date
        self.value = value
        self.label = label
        self.metadata = metadata
    }
    
    static func == (lhs: ChartDataPoint, rhs: ChartDataPoint) -> Bool {
        return lhs.x == rhs.x &&
               lhs.y == rhs.y &&
               lhs.date == rhs.date &&
               lhs.value == rhs.value &&
               lhs.label == rhs.label
        // Note: metadata comparison is omitted for simplicity
    }
}

struct TrendLineData {
    let points: [CGPoint]
    let slope: Double
    let intercept: Double
    let correlation: Double
    let equation: String
    
    var isIncreasing: Bool {
        return slope > 0
    }
    
    var isDecreasing: Bool {
        return slope < 0
    }
    
    var isStable: Bool {
        return abs(slope) < 0.1
    }
}

// MARK: - Citation Trend
// CitationTrend is defined in CitationHistory.swift

struct ChartStatistics {
    let totalDataPoints: Int
    let dateRange: (start: Date, end: Date)?
    let valueRange: (min: Int, max: Int)?
    let totalChange: Int
    let averageChange: Double
    let growthRate: Double
    let volatility: Double
    let trend: CitationTrend
}

// MARK: - Chart Configuration

struct ChartConfiguration: Codable {
    let timeRange: TimeRange
    let chartType: ChartType
    let showTrendLine: Bool
    let showDataPoints: Bool
    let showGrid: Bool
    let smoothLines: Bool
    let colorScheme: ColorScheme
    
    enum ChartType: String, CaseIterable, Codable {
        case line = "line"
        case bar = "bar"
        case area = "area"
        
        var displayName: String {
            switch self {
            case .line:
                return "Line Chart"
            case .bar:
                return "Bar Chart"
            case .area:
                return "Area Chart"
            }
        }
    }
    
    enum ColorScheme: String, CaseIterable, Codable {
        case blue = "blue"
        case green = "green"
        case purple = "purple"
        case orange = "orange"
        case red = "red"
        case system = "system"
        
        var primaryColor: NSColor {
            switch self {
            case .blue:
                return NSColor.systemBlue
            case .green:
                return NSColor.systemGreen
            case .purple:
                return NSColor.systemPurple
            case .orange:
                return NSColor.systemOrange
            case .red:
                return NSColor.systemRed
            case .system:
                return NSColor.controlAccentColor
            }
        }
        
        var secondaryColor: NSColor {
            return primaryColor.withAlphaComponent(0.3)
        }
    }
    
    static let `default` = ChartConfiguration(
        timeRange: .lastMonth,
        chartType: .line,
        showTrendLine: false,
        showDataPoints: true,
        showGrid: true,
        smoothLines: true,
        colorScheme: .system
    )
}

// MARK: - Chart Data Service

class ChartDataService {
    static let shared = ChartDataService()
    
    private init() {}
    
    // MARK: - Data Preparation
    
    /// Convert citation history to chart data
    func prepareChartData(
        from history: [CitationHistory],
        configuration: ChartConfiguration,
        scholarName: String = ""
    ) -> ChartData {
        guard !history.isEmpty else {
            return createEmptyChartData(title: scholarName)
        }

        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        let points = createDataPoints(from: sortedHistory)
        
        let xAxisLabels = generateXAxisLabels(for: sortedHistory, timeRange: configuration.timeRange)
        let yAxisRange = calculateYAxisRange(from: sortedHistory)
        let statistics = generateStatistics(from: sortedHistory)
        
        var trendLine: TrendLineData?
        if configuration.showTrendLine && sortedHistory.count >= 2 {
            trendLine = calculateTrendLine(from: points)
        }
        
        let title = scholarName.isEmpty ? "Citation History" : "\(scholarName) - Citations"
        let subtitle = generateSubtitle(from: statistics, timeRange: configuration.timeRange)
        
        let insights = ChartInsight.generateInsights(from: statistics)
        
        let chartData = ChartData(
            points: points,
            xAxisLabels: xAxisLabels,
            yAxisRange: yAxisRange,
            title: title,
            subtitle: subtitle,
            trendLine: trendLine,
            statistics: statistics,
            insights: insights
        )
        
        return chartData
    }
    
    /// Prepare chart data for multiple scholars comparison
    func prepareComparisonChartData(
        scholarHistories: [(scholar: Scholar, history: [CitationHistory])],
        configuration: ChartConfiguration
    ) -> [String: ChartData] {
        var chartDataMap: [String: ChartData] = [:]
        
        for (scholar, history) in scholarHistories {
            let chartData = prepareChartData(
                from: history,
                configuration: configuration,
                scholarName: scholar.name
            )
            chartDataMap[scholar.id] = chartData
        }
        
        return chartDataMap
    }
    
    // MARK: - Data Point Creation
    
    private func createDataPoints(from history: [CitationHistory]) -> [ChartDataPoint] {
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        return sortedHistory.enumerated().map { index, entry in
            let x = Double(index)
            let y = Double(entry.citationCount)
            let label = dateFormatter.string(from: entry.timestamp)
            
            let metadata: [String: Any] = [
                "source": entry.source.rawValue,
                "createdAt": entry.createdAt,
                "id": entry.id.uuidString
            ]
            
            return ChartDataPoint(
                x: x,
                y: y,
                date: entry.timestamp,
                value: entry.citationCount,
                label: label,
                metadata: metadata
            )
        }
    }
    
    // MARK: - Axis Generation
    
    private func generateXAxisLabels(for history: [CitationHistory], timeRange: TimeRange) -> [String] {
        guard !history.isEmpty else { return [] }
        
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        let dateFormatter = DateFormatter()
        
        // Adjust date format based on time range
        switch timeRange {
        case .lastWeek:
            dateFormatter.dateFormat = "E" // Day of week
        case .lastMonth:
            dateFormatter.dateFormat = "MMM d" // Month day
        case .lastQuarter, .lastYear:
            dateFormatter.dateFormat = "MMM yyyy" // Month year
        case .custom:
            dateFormatter.dateStyle = .short
        }
        
        // Generate labels with appropriate spacing
        let maxLabels = 8
        let step = max(1, sortedHistory.count / maxLabels)
        
        var labels: [String] = []
        for i in stride(from: 0, to: sortedHistory.count, by: step) {
            let entry = sortedHistory[i]
            labels.append(dateFormatter.string(from: entry.timestamp))
        }
        
        return labels
    }
    
    private func calculateYAxisRange(from history: [CitationHistory]) -> (min: Double, max: Double) {
        guard !history.isEmpty else { return (0, 100) }
        
        let values = history.map { $0.citationCount }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 100
        
        // Special handling for single data point or identical values
        if minValue == maxValue {
            let value = Double(maxValue)
            if value == 0 {
                return (0, 10) // Show range 0-10 for zero values
            } else {
                // Create a reasonable range around the single value
                let padding = max(value * 0.2, 10) // At least 20% or minimum 10 units
                return (max(0, value - padding), value + padding)
            }
        }
        
        // Add some padding to the range for multiple different values
        let padding = Double(maxValue - minValue) * 0.1
        let adjustedMin = max(0, Double(minValue) - padding)
        let adjustedMax = Double(maxValue) + padding
        
        return (adjustedMin, adjustedMax)
    }
    
    // MARK: - Trend Line Calculation
    
    func calculateTrendLine(from points: [ChartDataPoint]) -> TrendLineData? {
        guard points.count >= 2 else { return nil }
        
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + ($1.x * $1.y) }
        let sumXX = points.reduce(0) { $0 + ($1.x * $1.x) }
        let sumYY = points.reduce(0) { $0 + ($1.y * $1.y) }
        
        // Calculate slope and intercept using least squares method
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        
        // Calculate correlation coefficient
        let numerator = n * sumXY - sumX * sumY
        let denominatorR = sqrt((n * sumXX - sumX * sumX) * (n * sumYY - sumY * sumY))
        let correlation = denominatorR != 0 ? numerator / denominatorR : 0
        
        // Generate trend line points
        let minX = points.first?.x ?? 0
        let maxX = points.last?.x ?? 0
        let trendPoints = [
            CGPoint(x: minX, y: slope * minX + intercept),
            CGPoint(x: maxX, y: slope * maxX + intercept)
        ]
        
        // Generate equation string
        let equation = String(format: "y = %.2fx + %.2f", slope, intercept)
        
        return TrendLineData(
            points: trendPoints,
            slope: slope,
            intercept: intercept,
            correlation: correlation,
            equation: equation
        )
    }
    
    // MARK: - Statistics Generation
    
    private func generateStatistics(from history: [CitationHistory]) -> ChartStatistics {
        guard !history.isEmpty else {
            return ChartStatistics(
                totalDataPoints: 0,
                dateRange: nil,
                valueRange: nil,
                totalChange: 0,
                averageChange: 0,
                growthRate: 0,
                volatility: 0,
                trend: .stable
            )
        }
        
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        let values = sortedHistory.map { $0.citationCount }

        guard let firstEntry = sortedHistory.first,
              let lastEntry = sortedHistory.last,
              let minVal = values.min(),
              let maxVal = values.max() else {
            return ChartStatistics(
                totalDataPoints: 0,
                dateRange: (start: Date(), end: Date()),
                valueRange: (min: 0, max: 0),
                totalChange: 0,
                averageChange: 0,
                growthRate: 0,
                volatility: 0,
                trend: .stable
            )
        }

        let totalDataPoints = sortedHistory.count
        let dateRange = (start: firstEntry.timestamp, end: lastEntry.timestamp)
        let valueRange = (min: minVal, max: maxVal)
        
        let totalChange = valueRange.max - valueRange.min
        let averageChange = totalDataPoints > 1 ? Double(totalChange) / Double(totalDataPoints - 1) : 0
        
        let growthRate = valueRange.min > 0 ? (Double(totalChange) / Double(valueRange.min)) * 100 : 0
        
        // Calculate volatility (standard deviation of changes)
        let volatility = calculateVolatility(from: values)
        
        // Determine trend
        let trend = determineTrend(from: sortedHistory)
        
        return ChartStatistics(
            totalDataPoints: totalDataPoints,
            dateRange: dateRange,
            valueRange: valueRange,
            totalChange: totalChange,
            averageChange: averageChange,
            growthRate: growthRate,
            volatility: volatility,
            trend: trend
        )
    }
    
    private func calculateVolatility(from values: [Int]) -> Double {
        guard values.count > 1 else { return 0 }
        
        let changes = zip(values.dropFirst(), values).map { $0 - $1 }
        let mean = Double(changes.reduce(0, +)) / Double(changes.count)
        let variance = changes.reduce(0) { $0 + pow(Double($1) - mean, 2) } / Double(changes.count)
        
        return sqrt(variance)
    }
    
    private func determineTrend(from history: [CitationHistory]) -> CitationTrend {
        guard history.count >= 2 else { return .stable }
        
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        guard let first = sortedHistory.first, let last = sortedHistory.last else { return .stable }
        
        let change = last.citationCount - first.citationCount
        let changePercentage = first.citationCount > 0 ? abs(Double(change) / Double(first.citationCount)) * 100 : 0
        
        // Consider it stable if change is less than 5%
        if changePercentage < 5 {
            return .stable
        } else if change > 0 {
            return .increasing
        } else {
            return .decreasing
        }
    }
    
    // MARK: - Utility Methods
    
    private func createEmptyChartData(title: String) -> ChartData {
        let emptyStatistics = ChartStatistics(
            totalDataPoints: 0,
            dateRange: nil,
            valueRange: nil,
            totalChange: 0,
            averageChange: 0,
            growthRate: 0,
            volatility: 0,
            trend: .stable
        )
        
        return ChartData(
            points: [],
            xAxisLabels: [],
            yAxisRange: (0, 100),
            title: title,
            subtitle: "No data available",
            trendLine: nil as TrendLineData?,
            statistics: emptyStatistics,
            insights: []
        )
    }
    
    private func generateSubtitle(from statistics: ChartStatistics, timeRange: TimeRange) -> String {
        guard let dateRange = statistics.dateRange else {
            return "No data available"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        let startDate = dateFormatter.string(from: dateRange.start)
        let endDate = dateFormatter.string(from: dateRange.end)
        
        let changeText = statistics.totalChange >= 0 ? "+\(statistics.totalChange)" : "\(statistics.totalChange)"
        
        return "\(startDate) - \(endDate) • \(changeText) citations • \(statistics.trend.displayName)"
    }
    
    // MARK: - Data Filtering and Aggregation
    
    /// Filter citation history by date range
    func filterHistory(_ history: [CitationHistory], in timeRange: TimeRange, customStart: Date? = nil, customEnd: Date? = nil) -> [CitationHistory] {
        let dateRange: (start: Date, end: Date)
        
        if timeRange == .custom, let start = customStart, let end = customEnd {
            dateRange = (start, end)
        } else {
            dateRange = timeRange.dateRange
        }
        
        return history.filter { entry in
            entry.timestamp >= dateRange.start && entry.timestamp <= dateRange.end
        }
    }
    
    /// Aggregate citation history by time period (daily, weekly, monthly)
    func aggregateHistory(_ history: [CitationHistory], by period: AggregationPeriod) -> [CitationHistory] {
        guard !history.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        
        var aggregatedData: [String: [CitationHistory]] = [:]
        
        for entry in sortedHistory {
            let key = period.keyForDate(entry.timestamp, calendar: calendar)
            if aggregatedData[key] == nil {
                aggregatedData[key] = []
            }
            aggregatedData[key]?.append(entry)
        }
        
        // Create aggregated entries (using the latest entry in each period)
        return aggregatedData.compactMap { (key, entries) in
            guard let latest = entries.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return latest
        }.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Calculate moving average for smoothing data
    func calculateMovingAverage(_ history: [CitationHistory], windowSize: Int) -> [CitationHistory] {
        guard history.count >= windowSize else { return history }
        
        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
        var smoothedHistory: [CitationHistory] = []
        
        for i in 0..<sortedHistory.count {
            let startIndex = max(0, i - windowSize + 1)
            let endIndex = i + 1
            let window = Array(sortedHistory[startIndex..<endIndex])
            
            let averageCitations = window.reduce(0) { $0 + $1.citationCount } / window.count
            
            let smoothedEntry = CitationHistory(
                id: sortedHistory[i].id,
                scholarId: sortedHistory[i].scholarId,
                citationCount: averageCitations,
                timestamp: sortedHistory[i].timestamp,
                source: sortedHistory[i].source
            )
            
            smoothedHistory.append(smoothedEntry)
        }
        
        return smoothedHistory
    }
}

// MARK: - Aggregation Period

enum AggregationPeriod: String, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    
    var displayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }
    
    func keyForDate(_ date: Date, calendar: Calendar) -> String {
        switch self {
        case .daily:
            return AggregationPeriod.dailyFormatter.string(from: date)
        case .weekly:
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.year, from: date)
            return "\(year)-W\(weekOfYear)"
        case .monthly:
            return AggregationPeriod.monthlyFormatter.string(from: date)
        }
    }

    private static let dailyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()
}
