import SwiftUI

// MARK: - 本地 SwiftUICharts 组件集成
// 以下是从 SwiftUICharts 库中提取的核心组件

// MARK: - Colors
struct Colors {
    static let color1:Color = Color(hexString: "#E2FAE7")
    static let color1Accent:Color = Color(hexString: "#72BF82")
    static let color2:Color = Color(hexString: "#EEF1FF")
    static let color2Accent:Color = Color(hexString: "#4266E8")
    static let color3:Color = Color(hexString: "#FCECEA")
    static let color3Accent:Color = Color(hexString: "#E1614C")
    static let OrangeEnd:Color = Color(hexString: "#FF782C")
    static let OrangeStart:Color = Color(hexString: "#EC2301")
    static let LegendText:Color = Color(hexString: "#A7A6A8")
    static let LegendColor:Color = Color(hexString: "#E8E7EA")
    static let LegendDarkColor:Color = Color(hexString: "#545454")
    static let IndicatorKnob:Color = Color(hexString: "#FF57A6")
    static let GradientUpperBlue:Color = Color(hexString: "#C2E8FF")
    static let GradinetUpperBlue1:Color = Color(hexString: "#A8E1FF")
    static let GradientPurple:Color = Color(hexString: "#7B75FF")
    static let GradientNeonBlue:Color = Color(hexString: "#6FEAFF")
    static let GradientLowerBlue:Color = Color(hexString: "#F1F9FF")
    static let DarkPurple:Color = Color(hexString: "#1B205E")
    static let BorderBlue:Color = Color(hexString: "#4EBCFF")
}

// MARK: - GradientColor
struct GradientColor {
    let start: Color
    let end: Color
    
    init(start: Color, end: Color) {
        self.start = start
        self.end = end
    }
    
    func getGradient() -> Gradient {
        return Gradient(colors: [start, end])
    }
}

// MARK: - GradientColors
struct GradientColors {
    static let orange = GradientColor(start: Colors.OrangeStart, end: Colors.OrangeEnd)
    static let blue = GradientColor(start: Colors.GradientPurple, end: Colors.GradientNeonBlue)
    static let green = GradientColor(start: Color(hexString: "0BCDF7"), end: Color(hexString: "A2FEAE"))
    static let blu = GradientColor(start: Color(hexString: "0591FF"), end: Color(hexString: "29D9FE"))
    static let bluPurpl = GradientColor(start: Color(hexString: "4ABBFB"), end: Color(hexString: "8C00FF"))
    static let purple = GradientColor(start: Color(hexString: "741DF4"), end: Color(hexString: "C501B0"))
    static let prplPink = GradientColor(start: Color(hexString: "BC05AF"), end: Color(hexString: "FF1378"))
    static let prplNeon = GradientColor(start: Color(hexString: "FE019A"), end: Color(hexString: "FE0BF4"))
    static let orngPink = GradientColor(start: Color(hexString: "FF8E2D"), end: Color(hexString: "FF4E7A"))
}

// MARK: - ChartStyle
class ChartStyle {
    var backgroundColor: Color
    var accentColor: Color
    var gradientColor: GradientColor
    var textColor: Color
    var legendTextColor: Color
    var dropShadowColor: Color
    weak var darkModeStyle: ChartStyle?
    
    init(backgroundColor: Color, accentColor: Color, secondGradientColor: Color, textColor: Color, legendTextColor: Color, dropShadowColor: Color){
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.gradientColor = GradientColor(start: accentColor, end: secondGradientColor)
        self.textColor = textColor
        self.legendTextColor = legendTextColor
        self.dropShadowColor = dropShadowColor
    }
    
    init(backgroundColor: Color, accentColor: Color, gradientColor: GradientColor, textColor: Color, legendTextColor: Color, dropShadowColor: Color){
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.gradientColor = gradientColor
        self.textColor = textColor
        self.legendTextColor = legendTextColor
        self.dropShadowColor = dropShadowColor
    }
    
    init(formSize: CGSize){
        self.backgroundColor = Color.white
        self.accentColor = Colors.OrangeStart
        self.gradientColor = GradientColors.orange
        self.legendTextColor = Color.gray
        self.textColor = Color.black
        self.dropShadowColor = Color.gray
    }
}

// MARK: - ChartData
class ChartData: ObservableObject, Identifiable {
    @Published var points: [(String,Double)]
    var valuesGiven: Bool = false
    var ID = UUID()
    
    init<N: BinaryFloatingPoint>(points:[N]) {
        self.points = points.map{("", Double($0))}
    }
    init<N: BinaryInteger>(values:[(String,N)]){
        self.points = values.map{($0.0, Double($0.1))}
        self.valuesGiven = true
    }
    init<N: BinaryFloatingPoint>(values:[(String,N)]){
        self.points = values.map{($0.0, Double($0.1))}
        self.valuesGiven = true
    }
    init<N: BinaryInteger>(numberValues:[(N,N)]){
        self.points = numberValues.map{(String($0.0), Double($0.1))}
        self.valuesGiven = true
    }
    init<N: BinaryFloatingPoint & LosslessStringConvertible>(numberValues:[(N,N)]){
        self.points = numberValues.map{(String($0.0), Double($0.1))}
        self.valuesGiven = true
    }
    
    func onlyPoints() -> [Double] {
        return self.points.map{ $0.1 }
    }
}

// MARK: - Styles
struct Styles {
    static let lineChartStyleOne = ChartStyle(
        backgroundColor: Color.white,
        accentColor: Colors.OrangeStart,
        secondGradientColor: Colors.OrangeEnd,
        textColor: Color.black,
        legendTextColor: Color.gray,
        dropShadowColor: Color.gray)
    
    static let lineViewDarkMode = ChartStyle(
        backgroundColor: Color.black,
        accentColor: Colors.OrangeStart,
        secondGradientColor: Colors.OrangeEnd,
        textColor: Color.white,
        legendTextColor: Color.white,
        dropShadowColor: Color.gray)
}

// MARK: - HapticFeedback
class HapticFeedback {
    #if os(watchOS)
    static func playSelection() -> Void {
        WKInterfaceDevice.current().play(.click)
    }
    #elseif os(iOS)
    static func playSelection() -> Void {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    #else
    static func playSelection() -> Void {
        //No-op
    }
#endif
}

// MARK: - Color Extension
extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}


/// 学者引用量折线图（单学者 LineView，按库示例绘制）
struct ScholarsGrowthLineChartView: View {
    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var selectedDays: Int = 30
    @State private var selectedScholarId: String? = nil

    private let supportedPeriods: [Int] = [7, 30, 90]

    var body: some View {
        // 🔵 蓝色区域：整个ScholarsGrowthLineChartView主容器 - 图表组件整体布局
        VStack(alignment: .leading, spacing: 0) {
            // 顶部控制区域（时间选择器 + 学者选择器）
            topControls
                .padding(.horizontal)
                .padding(.top, 0)

            // 🔴 红色区域：图表区域容器 - 包含图表内容
            chartSection
                .frame(maxWidth: .infinity, alignment: .leading)
                // .background(Color.red.opacity(0.3)) // 调试：图表区域背景
            
            // 添加Spacer让内容从顶部开始，而不是居中
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // .background(Color.blue.opacity(0.3)) // 调试：整个ScholarsGrowthLineChartView背景
        .onAppear {
            if selectedScholarId == nil { selectedScholarId = dataManager.scholars.first?.id }
        }
    }

    private var topControls: some View {
        VStack(spacing: 12) {
            // 周期
            HStack {
                Picker("time_range".localized, selection: $selectedDays) {
                    ForEach(supportedPeriods, id: \.self) { d in
                        Text(label(for: d)).tag(d)
                    }
                }
                .pickerStyle(.segmented)
            }

            // 学者选择（单选）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dataManager.scholars, id: \.id) { s in
                        let isOn = (selectedScholarId == s.id)
                        let grad = gradientForScholarId(s.id)
                        Button(action: {
                            selectedScholarId = s.id
                        }) {
                            HStack(spacing: 6) {
                                LinearGradient(gradient: Gradient(colors: [grad.start, grad.end]), startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 16, height: 16)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().stroke(isOn ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                                Text(s.displayName)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isOn ? Color(.systemGray5) : Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }

    private func label(for days: Int) -> String {
        switch days {
        case 7: return "period_7_days".localized
        case 30: return "period_30_days".localized
        case 90: return "period_90_days".localized
        default: return String(format: "period_days_format".localized, days)
        }
    }

    // 🔴 红色区域：图表区域容器 - 包含图表内容
    private var chartSection: some View {
        GeometryReader { geometry in
            Group {
                if let sid = selectedScholarId, let chart = lineChart(for: sid) { 
                    chart
                        .id("chart-\(sid)-\(selectedDays)") // 强制重新创建视图，避免动画冲突
                } else { 
                    emptyState 
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // 通知父视图图表区域的实际高度
                let chartHeight = geometry.size.height
                // 🚀 优化：移除频繁的高度调试打印
                #if DEBUG_CHART_VERBOSE
                print(String(format: "debug_chart_height".localized, "\(chartHeight)"))
                #endif
            }
        }
        // .frame(height: 500) // 设置一个合理的基础高度，让图表有足够的显示空间
        .padding(.horizontal, 16) // 控制容器水平内边距
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.title)
                .foregroundColor(.secondary)
            Text(localizationManager.localized("no_data_available"))
                .font(.headline)
            Text(localizationManager.localized("add_scholars_first"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity) // 只控制宽度，不限制高度
        .padding(.horizontal, 16) // 控制容器水平内边距
    }

    private func lineChart(for scholarId: String) -> AnyView? {
        guard let scholar = dataManager.getScholar(id: scholarId) else { return nil }
        let history = dataManager.getHistory(for: scholarId, days: selectedDays).sorted { $0.timestamp < $1.timestamp }
        guard !history.isEmpty else { return nil }

        // 数据验证和清理：确保数据稳定，避免动画错误
        let cleanedHistory = history.filter { $0.citationCount >= 0 && $0.timestamp.timeIntervalSince1970 > 0 }
        guard !cleanedHistory.isEmpty else { return nil }
        
        // 强制整数：将原始值取整，传入 LineView，并用整数格式化
        let rawValues = cleanedHistory.map { max(0, $0.citationCount) }
        let minValue = rawValues.min() ?? 0
        let maxValue = rawValues.max() ?? 0
        
        // 强制创建整数友好的数据范围，确保Y轴刻度为整数
        let range = maxValue - minValue
        
        // 如果范围太小（小于4），扩展到至少5的范围
        let targetRange = max(5, range)
        let centerValue = (minValue + maxValue) / 2
        let newMin = max(0, centerValue - targetRange / 2)
        let _ = newMin + targetRange // 计算但不使用，避免警告
        
        // 确保边界都是整数，且范围能被5整除（便于生成5个整数刻度）
        let adjustedMin = Int(newMin)
        let adjustedMax = adjustedMin + ((targetRange + 4) / 5) * 5 // 向上取整到5的倍数
        
        let values: [Double] = rawValues.map { Double($0) }
        let dates = cleanedHistory.map { $0.timestamp }
        
        // 🚀 优化：移除频繁的调试打印，避免影响性能
        #if DEBUG_CHART_VERBOSE
        print("📊 [Debug] Scholar: \(scholar.displayName)")
        print("📊 [Debug] Raw values: \(rawValues)")
        print("📊 [Debug] Double values: \(values)")
        print("📊 [Debug] Dates: \(dates)")
        print("📊 [Debug] Min: \(minValue), Max: \(maxValue), Range: \(range)")
        print("📊 [Debug] Adjusted Min: \(adjustedMin), Max: \(adjustedMax)")
        #endif
        
        let title = scholar.displayName
        let legend = label(for: selectedDays)

        // 颜色样式（不同学者不同颜色）
        let grad = gradientForScholarId(scholarId)
        let style = ChartStyle(
            backgroundColor: .clear,   // transparent so the Liquid Glass card shows through
            accentColor: grad.start,
            secondGradientColor: grad.end,
            textColor: Color.primary,
            legendTextColor: Color.secondary,
            dropShadowColor: Color.clear
        )

        // 横坐标标签（起点/中点/终点）
        let df = DateFormatter(); df.dateFormat = "MM/dd"

        return AnyView(
            // 🟡 黄色区域：LineView包装VStack - 图表外层容器
            VStack(spacing: 0) {
                // 🟢 绿色区域：SwiftUICharts LineView - 实际图表组件
                LineView(
                    data: values,
                    title: title,
                    legend: legend,
                    style: style,
                    valueSpecifier: "%.0f",
                    legendSpecifier: "%.0f",
                    dates: dates
                )
                .transaction { tx in 
                    tx.animation = nil 
                    tx.disablesAnimations = true
                }
                .animation(nil, value: values)
                .animation(nil, value: selectedDays)
                // 尝试使用环境变量强制整数格式
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                // .background(Color.green.opacity(0.3)) // 调试：LineView背景
            }
            .frame(maxWidth: .infinity) // 让VStack占满容器宽度
            // .background(Color.yellow.opacity(0.3)) // 调试：VStack背景
        )
    }

    // 为学者映射稳定的渐变色
    private func gradientForScholarId(_ id: String) -> GradientColor {
        let palette: [GradientColor] = [
            GradientColors.blue,
            GradientColors.green,
            GradientColors.orngPink,
            GradientColors.purple,
            GradientColors.bluPurpl,
            GradientColors.prplNeon,
        ]
        let idx = stableIndex(for: id, modulo: palette.count)
        return palette[idx]
    }

    private func stableIndex(for text: String, modulo: Int) -> Int {
        var acc: UInt64 = 1469598103934665603 // FNV-1a offset
        for u in text.utf8 { acc ^= UInt64(u); acc &*= 1099511628211 }
        return Int(acc % UInt64(max(1, modulo)))
    }
}

// MARK: - 本地 LineView 实现
struct LineView: View {
    @ObservedObject var data: ChartData
    public var title: String?
    public var legend: String?
    public var style: ChartStyle
    public var darkModeStyle: ChartStyle
    public var valueSpecifier: String
    public var legendSpecifier: String
    public var dates: [Date] = []
    
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @State private var showLegend = false
    @State private var dragLocation:CGPoint = .zero
    @State private var indicatorLocation:CGPoint = .zero
    @State private var closestPoint: CGPoint = .zero
    @State private var opacity:Double = 0
    @State private var currentDataNumber: Double = 0
    @State private var hideHorizontalLines: Bool = false
    @State private var currentDateString: String = ""
    
    public init(data: [Double],
                title: String? = nil,
                legend: String? = nil,
                style: ChartStyle = Styles.lineChartStyleOne,
                valueSpecifier: String? = "%.1f",
                legendSpecifier: String? = "%.2f",
                dates: [Date] = []) {
        
        self.data = ChartData(points: data)
        self.title = title
        self.legend = legend
        self.style = style
        self.valueSpecifier = valueSpecifier ?? "%.1f"
        self.legendSpecifier = legendSpecifier ?? "%.2f"
        self.dates = dates
        self.darkModeStyle = style.darkModeStyle ?? Styles.lineViewDarkMode
    }
    
    public var body: some View {
        GeometryReader{ geometry in
            VStack(alignment: .leading, spacing: 8) {
                Group{
                    if let title = self.title {
                        Text(title)
                            .font(.headline)
                            .bold().foregroundColor(self.colorScheme == .dark ? self.darkModeStyle.textColor : self.style.textColor)
                    }
                    if let legend = self.legend {
                        Text(legend)
                            .font(.caption)
                            .foregroundColor(self.colorScheme == .dark ? self.darkModeStyle.legendTextColor : self.style.legendTextColor)
                    }
                }.offset(x: 0, y: 20)
                ZStack{
                    GeometryReader{ reader in
                        Rectangle()
                            .foregroundColor(self.colorScheme == .dark ? self.darkModeStyle.backgroundColor : self.style.backgroundColor)
                        if(self.showLegend){
                            Legend(data: self.data,
                                   frame: .constant(reader.frame(in: .local)), hideHorizontalLines: self.$hideHorizontalLines, specifier: legendSpecifier)
                                .transition(.opacity)
                                .animation(.easeOut(duration: 1).delay(1), value: showLegend)
                        }
                        Line(data: self.data,
                             frame: .constant(CGRect(x: 0, y: 0, width: reader.frame(in: .local).width - self.calculateDynamicOffset(), height: reader.frame(in: .local).height + 25)),
                             touchLocation: self.$indicatorLocation,
                             showIndicator: self.$hideHorizontalLines,
                             minDataValue: .constant(nil),
                             maxDataValue: .constant(nil),
                             showBackground: false,
                             gradient: self.style.gradientColor
                        )
                        .offset(x: self.calculateDynamicOffset(), y: 0)
                        .onAppear(){
                            self.showLegend = true
                        }
                        .onDisappear(){
                            self.showLegend = false
                        }
                    }
                    .frame(width: geometry.frame(in: .local).size.width, height: 240)
                    .offset(x: 0, y: 40 )
                    MagnifierRect(currentNumber: self.$currentDataNumber, valueSpecifier: self.valueSpecifier, currentDate: self.currentDateString)
                        .opacity(self.opacity)
                        .offset(x: self.dragLocation.x - geometry.frame(in: .local).size.width/2, y: 36)
                }
                .frame(width: geometry.frame(in: .local).size.width, height: 240)
                .gesture(DragGesture()
                .onChanged({ value in
                    self.dragLocation = value.location
                    self.indicatorLocation = CGPoint(x: Swift.max(value.location.x-self.calculateDynamicOffset(),0), y: 32)
                    self.opacity = 1
                    self.closestPoint = self.getClosestDataPoint(toPoint: value.location, width: geometry.frame(in: .local).size.width-self.calculateDynamicOffset(), height: 240)
                    self.hideHorizontalLines = true
                    
                    // 计算当前拖拽位置对应的日期
                    self.currentDateString = self.getCurrentDateString(for: value.location, width: geometry.frame(in: .local).size.width)
                })
                    .onEnded({ value in
                        self.opacity = 0
                        self.hideHorizontalLines = false
                        self.currentDateString = ""
                    })
                )
                
                // 横坐标标签 - 显示日期
                HStack {
                    ForEach(0..<data.points.count, id: \.self) { index in
                        if index == 0 || index == data.points.count - 1 || index == data.points.count / 2 {
                            Text(formatDateForXAxis(index: index))
                                .font(.caption2)
                                .foregroundColor(self.colorScheme == .dark ? self.darkModeStyle.legendTextColor : self.style.legendTextColor)
                                .frame(maxWidth: .infinity)
                        } else {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 35)
            }
        }
    }
    
    func getClosestDataPoint(toPoint: CGPoint, width:CGFloat, height: CGFloat) -> CGPoint {
        let points = self.data.onlyPoints()
        guard points.count > 1 else { return .zero }
        guard width > 0, height > 0 else { return .zero }

        let safeCount = CGFloat(max(points.count - 1, 1))
        let stepWidth: CGFloat = width / safeCount
        guard stepWidth.isFinite, stepWidth > 0 else { return .zero }

        let maxValue = points.max() ?? 0
        let minValue = points.min() ?? 0
        let range = CGFloat(max(maxValue - minValue, 1))
        let stepHeight: CGFloat = height / range

        let calculatedIndex = max(0, (toPoint.x - 15) / stepWidth)
        let clampedIndex = min(Int(floor(calculatedIndex)), points.count - 1)

        if clampedIndex >= 0 && clampedIndex < points.count {
            self.currentDataNumber = points[clampedIndex]
            let x = CGFloat(clampedIndex) * stepWidth
            let y = CGFloat(points[clampedIndex] - minValue) * stepHeight
            return CGPoint(x: x, y: y)
        }
        return .zero
    }
    
    // 获取当前拖拽位置对应的日期字符串
    func getCurrentDateString(for location: CGPoint, width: CGFloat) -> String {
        let points = self.data.onlyPoints()
        guard points.count > 1 else { return "" }
        
        // 使用安全的计算，防止溢出
        let safeCount = CGFloat(max(points.count - 1, 1))
        let stepWidth: CGFloat = width / safeCount
        
        // 使用安全的计算，防止溢出
        let offset = self.calculateDynamicOffset()
        let safeLocationX = max(min(location.x, CGFloat.greatestFiniteMagnitude), -CGFloat.greatestFiniteMagnitude)
        let safeOffset = max(min(offset, CGFloat.greatestFiniteMagnitude), -CGFloat.greatestFiniteMagnitude)
        let calculatedIndex = (safeLocationX - safeOffset) / stepWidth
        let clampedIndex = max(min(Int(floor(calculatedIndex)), Int.max - 1), 0)
        
        if clampedIndex >= 0 && clampedIndex < points.count && clampedIndex < dates.count {
            return formatDateForXAxis(index: clampedIndex)
        }
        return ""
    }
    
    func formatDateForXAxis(index: Int) -> String {
        guard index < dates.count else { return "\(index + 1)" }
        let date = dates[index]
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
    // 计算动态偏移量，适应Y轴标签宽度
    func calculateDynamicOffset() -> CGFloat {
        let points = self.data.onlyPoints()
        guard let max = points.max(), let min = points.min() else { return 30 }
        
        // 计算Y轴标签的最大宽度
        let step = Double(max - min) / 4
        let legendValues = [min + step * 0, min + step * 1, min + step * 2, min + step * 3, min + step * 4]
        
        var maxWidth: CGFloat = 0
        for value in legendValues {
            let formattedText = formatNumber(value)
            // 估算文本宽度：每个字符约8像素，加上一些边距
            let estimatedWidth = CGFloat(formattedText.count) * 8 + 10
            maxWidth = Swift.max(maxWidth, estimatedWidth)
        }
        
        // 确保最小宽度为30像素，最大不超过70像素（增加以容纳更长的标签）
        return Swift.max(30, Swift.min(70, maxWidth))
    }
    
    // 格式化数字为简写形式 (k, m, b) - 用于LineView，显示4位有效数字
    func formatNumber(_ number: Double) -> String {
        let absNumber = abs(number)
        
        // 根据数值大小选择单位和计算小数位数
        if absNumber >= 1_000_000_000 {
            // 十亿级别
            let value = number / 1_000_000_000
            let integerDigits = String(Int(abs(value))).count
            let decimalPlaces = max(0, 4 - integerDigits)
            return String(format: "%.\(decimalPlaces)fb", value)
        } else if absNumber >= 1_000_000 {
            // 百万级别
            let value = number / 1_000_000
            let integerDigits = String(Int(abs(value))).count
            let decimalPlaces = max(0, 4 - integerDigits)
            return String(format: "%.\(decimalPlaces)fm", value)
        } else if absNumber >= 1_000 {
            // 千级别：1.081k (1位整数+3位小数) 或 987.9k (3位整数+1位小数)
            let value = number / 1_000
            let integerDigits = String(Int(abs(value))).count
            let decimalPlaces = max(0, 4 - integerDigits)
            return String(format: "%.\(decimalPlaces)fk", value)
        } else {
            // 小于1000：直接显示整数
            return String(format: "%.0f", number)
        }
    }
}

// MARK: - 简化的 Legend 组件
struct Legend: View {
    @ObservedObject var data: ChartData
    @Binding var frame: CGRect
    @Binding var hideHorizontalLines: Bool
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var specifier: String = "%.0f"
    let padding:CGFloat = 3
    
    // 格式化数字为简写形式 (k, m, b)，显示4位有效数字
    func formatNumber(_ number: Double) -> String {
        let absNumber = abs(number)
        
        // 根据数值大小选择单位和计算小数位数
        if absNumber >= 1_000_000_000 {
            // 十亿级别
            let value = number / 1_000_000_000
            let integerDigits = String(Int(abs(value))).count
            let decimalPlaces = max(0, 4 - integerDigits)
            return String(format: "%.\(decimalPlaces)fb", value)
        } else if absNumber >= 1_000_000 {
            // 百万级别
            let value = number / 1_000_000
            let integerDigits = String(Int(abs(value))).count
            let decimalPlaces = max(0, 4 - integerDigits)
            return String(format: "%.\(decimalPlaces)fm", value)
        } else if absNumber >= 1_000 {
            // 千级别：1.081k (1位整数+3位小数) 或 987.9k (3位整数+1位小数)
            let value = number / 1_000
            let integerDigits = String(Int(abs(value))).count
            let decimalPlaces = max(0, 4 - integerDigits)
            return String(format: "%.\(decimalPlaces)fk", value)
        } else {
            // 小于1000：直接显示整数
            return String(format: "%.0f", number)
        }
    }
    
    // 计算Y轴标签的最大宽度
    func calculateMaxYLabelWidth() -> CGFloat {
        guard let legend = getYLegend() else { return 30 } // 默认30像素
        
        var maxWidth: CGFloat = 0
        for value in legend {
            let formattedText = formatNumber(value)
            // 估算文本宽度：每个字符约8像素，加上一些边距
            let estimatedWidth = CGFloat(formattedText.count) * 8 + 10
            maxWidth = Swift.max(maxWidth, estimatedWidth)
        }
        
        // 确保最小宽度为30像素，最大不超过70像素（增加以容纳更长的标签）
        return Swift.max(30, Swift.min(70, maxWidth))
    }

    var stepWidth: CGFloat {
        if data.points.count < 2 {
            return 0
        }
        return frame.size.width / CGFloat(data.points.count-1)
    }
    var stepHeight: CGFloat {
        let points = self.data.onlyPoints()
        if let min = points.min(), let max = points.max(), min != max {
            if (min < 0){
                return (frame.size.height-padding) / CGFloat(max - min)
            }else{
                return (frame.size.height-padding) / CGFloat(max - min)
            }
        }
        return 0
    }
    
    var min: CGFloat {
        let points = self.data.onlyPoints()
        return CGFloat(points.min() ?? 0)
    }
    
    var body: some View {
        ZStack(alignment: .topLeading){
            ForEach((0...4), id: \.self) { height in
                HStack(alignment: .center){
                    Text(formatNumber(self.getYLegendSafe(height: height))).offset(x: 0, y: self.getYposition(height: height) )
                        .foregroundColor(Colors.LegendText)
                        .font(.caption)
                    self.line(atHeight: self.getYLegendSafe(height: height), width: self.frame.width)
                        .stroke(self.colorScheme == .dark ? Colors.LegendDarkColor : Colors.LegendColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5,height == 0 ? 0 : 10]))
                        .opacity((self.hideHorizontalLines && height != 0) ? 0 : 1)
                        .rotationEffect(.degrees(180), anchor: .center)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        .animation(.easeOut(duration: 0.2), value: hideHorizontalLines)
                        .clipped()
                }
               
            }
            
        }
    }
    
    func getYLegendSafe(height:Int)->CGFloat{
        if let legend = getYLegend() {
            return CGFloat(legend[height])
        }
        return 0
    }
    
    func getYposition(height: Int)-> CGFloat {
        if let legend = getYLegend() {
            return (self.frame.height-((CGFloat(legend[height]) - min)*self.stepHeight))-(self.frame.height/2)
        }
        return 0
       
    }
    
    func line(atHeight: CGFloat, width: CGFloat) -> Path {
        var hLine = Path()
        hLine.move(to: CGPoint(x:5, y: (atHeight-min)*stepHeight))
        hLine.addLine(to: CGPoint(x: width, y: (atHeight-min)*stepHeight))
        return hLine
    }
    
    func getYLegend() -> [Double]? {
        let points = self.data.onlyPoints()
        guard let max = points.max() else { return nil }
        guard let min = points.min() else { return nil }
        let step = Double(max - min)/4
        return [min+step * 0, min+step * 1, min+step * 2, min+step * 3, min+step * 4]
    }
}

// MARK: - 简化的 Line 组件
struct Line: View {
    @ObservedObject var data: ChartData
    @Binding var frame: CGRect
    @Binding var touchLocation: CGPoint
    @Binding var showIndicator: Bool
    @Binding var minDataValue: Double?
    @Binding var maxDataValue: Double?
    @State private var showFull: Bool = false
    @State var showBackground: Bool = true
    var gradient: GradientColor = GradientColor(start: Colors.GradientPurple, end: Colors.GradientNeonBlue)
    var index:Int = 0
    let padding:CGFloat = 30
    var curvedLines: Bool = true
    var stepWidth: CGFloat {
        if data.points.count < 2 {
            return 0
        }
        return frame.size.width / CGFloat(data.points.count-1)
    }
    var stepHeight: CGFloat {
        var min: Double?
        var max: Double?
        let points = self.data.onlyPoints()
        if let minVal = minDataValue, let maxVal = maxDataValue {
            min = minVal
            max = maxVal
        }else if let minPoint = points.min(), let maxPoint = points.max(), minPoint != maxPoint {
            min = minPoint
            max = maxPoint
        }else {
            return 0
        }
        if let min = min, let max = max, min != max {
            if (min <= 0){
                return (frame.size.height-padding) / CGFloat(max - min)
            }else{
                return (frame.size.height-padding) / CGFloat(max - min)
            }
        }
        return 0
    }
    var path: Path {
        let points = self.data.onlyPoints()
        return curvedLines ? Path.quadCurvedPathWithPoints(points: points, step: CGPoint(x: stepWidth, y: stepHeight), globalOffset: minDataValue) : Path.linePathWithPoints(points: points, step: CGPoint(x: stepWidth, y: stepHeight))
    }
    var closedPath: Path {
        let points = self.data.onlyPoints()
        return curvedLines ? Path.quadClosedCurvedPathWithPoints(points: points, step: CGPoint(x: stepWidth, y: stepHeight), globalOffset: minDataValue) : Path.closedLinePathWithPoints(points: points, step: CGPoint(x: stepWidth, y: stepHeight))
    }
    
    public var body: some View {
        ZStack {
            if(self.showFull && self.showBackground){
                self.closedPath
                    .fill(LinearGradient(gradient: Gradient(colors: [Colors.GradientUpperBlue, .white]), startPoint: .bottom, endPoint: .top))
                    .rotationEffect(.degrees(180), anchor: .center)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .transition(.opacity)
                    .animation(.easeIn(duration: 1.6), value: showFull)
            }
            self.path
                .trim(from: 0, to: self.showFull ? 1:0)
                .stroke(LinearGradient(gradient: gradient.getGradient(), startPoint: .leading, endPoint: .trailing) ,style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                .rotationEffect(.degrees(180), anchor: .center)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .animation(.easeOut(duration: 1.2).delay(Double(self.index)*0.4), value: showFull)
                .onAppear {
                    self.showFull = true
            }
            .onDisappear {
                self.showFull = false
            }
            if(self.showIndicator) {
                IndicatorPoint()
                    .position(self.getClosestPointOnPath(touchLocation: self.touchLocation))
                    .rotationEffect(.degrees(180), anchor: .center)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
    }
    
    func getClosestPointOnPath(touchLocation: CGPoint) -> CGPoint {
        let closest = self.path.point(to: touchLocation.x)
        return closest
    }
}

// MARK: - 简化的 IndicatorPoint 组件
struct IndicatorPoint: View {
    var body: some View {
        ZStack{
            Circle()
                .fill(Colors.IndicatorKnob)
            Circle()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4))
        }
        .frame(width: 14, height: 14)
        .shadow(color: Colors.LegendColor, radius: 6, x: 0, y: 6)
    }
}

// MARK: - 简化的 MagnifierRect 组件
struct MagnifierRect: View {
    @Binding var currentNumber: Double
    var valueSpecifier: String
    var currentDate: String = ""
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    
    public var body: some View {
        ZStack{
            // Y轴数据 - 顶部显示
            Text("\(self.currentNumber, specifier: valueSpecifier)")
                .font(.system(size: 18, weight: .bold))
                .offset(x: 0, y: -110)
                .foregroundColor(self.colorScheme == .dark ? Color.white : Color.black)
            
            // X轴数据 - 底部显示
            if !currentDate.isEmpty {
                Text(currentDate)
                    .font(.system(size: 14, weight: .medium))
                    .offset(x: 0, y: 110)
                    .foregroundColor(self.colorScheme == .dark ? Color.white : Color.black)
            }
            
            // 背景框
            if (self.colorScheme == .dark ){
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white, lineWidth: self.colorScheme == .dark ? 2 : 0)
                    .frame(width: 80, height: 280)
            }else{
                RoundedRectangle(cornerRadius: 16)
                    .frame(width: 80, height: 300)
                    .foregroundColor(Color.white)
                    .shadow(color: Colors.LegendText, radius: 12, x: 0, y: 6 )
                    .blendMode(.multiply)
            }
        }
        .offset(x: 0, y: -15)
    }
}

// MARK: - Path 扩展
extension Path {
    func trimmedPath(for percent: CGFloat) -> Path {
        // Guard against NaN/infinite values that would crash trimmedPath
        guard percent.isFinite else { return Path() }

        let boundsDistance: CGFloat = 0.001
        let completion: CGFloat = 1 - boundsDistance

        let pct = percent > 1 ? 0 : (percent < 0 ? 1 : percent)

        let start = pct > completion ? completion : pct - boundsDistance
        let end = pct > completion ? 1 : pct + boundsDistance

        // Clamp to valid range [0, 1]
        let safeStart = max(0, min(1, start))
        let safeEnd = max(safeStart, min(1, end))
        return trimmedPath(from: safeStart, to: safeEnd)
    }

    func point(for percent: CGFloat) -> CGPoint {
        guard percent.isFinite else { return .zero }
        let path = trimmedPath(for: percent)
        return CGPoint(x: path.boundingRect.midX, y: path.boundingRect.midY)
    }
    
    func point(to maxX: CGFloat) -> CGPoint {
        let total = length
        guard total > 0, total.isFinite else { return .zero }
        let sub = length(to: maxX)
        guard sub.isFinite else { return .zero }
        let percent = sub / total
        guard percent.isFinite else { return .zero }
        return point(for: percent)
    }
    
    var length: CGFloat {
        var ret: CGFloat = 0.0
        var start: CGPoint?
        var point = CGPoint.zero
        
        forEach { ele in
            switch ele {
            case .move(let to):
                if start == nil {
                    start = to
                }
                point = to
            case .line(let to):
                ret += point.line(to: to)
                point = to
            case .quadCurve(let to, let control):
                ret += point.quadCurve(to: to, control: control)
                point = to
            case .curve(let to, let control1, let control2):
                ret += point.curve(to: to, control1: control1, control2: control2)
                point = to
            case .closeSubpath:
                if let to = start {
                    ret += point.line(to: to)
                    point = to
                }
                start = nil
            }
        }
        return ret
    }
    
    func length(to maxX: CGFloat) -> CGFloat {
        var ret: CGFloat = 0.0
        var start: CGPoint?
        var point = CGPoint.zero
        var finished = false
        
        forEach { ele in
            if finished {
                return
            }
            switch ele {
            case .move(let to):
                if to.x > maxX {
                    finished = true
                    return
                }
                if start == nil {
                    start = to
                }
                point = to
            case .line(let to):
                if to.x > maxX {
                    finished = true
                    ret += point.line(to: to, x: maxX)
                    return
                }
                ret += point.line(to: to)
                point = to
            case .quadCurve(let to, let control):
                if to.x > maxX {
                    finished = true
                    ret += point.quadCurve(to: to, control: control, x: maxX)
                    return
                }
                ret += point.quadCurve(to: to, control: control)
                point = to
            case .curve(let to, let control1, let control2):
                if to.x > maxX {
                    finished = true
                    ret += point.curve(to: to, control1: control1, control2: control2, x: maxX)
                    return
                }
                ret += point.curve(to: to, control1: control1, control2: control2)
                point = to
            case .closeSubpath:
                // Safely handle closeSubpath instead of crashing
                if let to = start {
                    ret += point.line(to: to)
                    point = to
                }
                start = nil
            }
        }
        return ret
    }
    
    static func quadCurvedPathWithPoints(points:[Double], step:CGPoint, globalOffset: Double? = nil) -> Path {
        var path = Path()
        if (points.count < 2){
            return path
        }
        guard let offset = globalOffset ?? points.min() else { return path }
        var p1 = CGPoint(x: 0, y: CGFloat(points[0]-offset)*step.y)
        path.move(to: p1)
        for pointIndex in 1..<points.count {
            let p2 = CGPoint(x: step.x * CGFloat(pointIndex), y: step.y*CGFloat(points[pointIndex]-offset))
            let midPoint = CGPoint.midPointForPoints(p1: p1, p2: p2)
            path.addQuadCurve(to: midPoint, control: CGPoint.controlPointForPoints(p1: midPoint, p2: p1))
            path.addQuadCurve(to: p2, control: CGPoint.controlPointForPoints(p1: midPoint, p2: p2))
            p1 = p2
        }
        return path
    }
    
    static func quadClosedCurvedPathWithPoints(points:[Double], step:CGPoint, globalOffset: Double? = nil) -> Path {
        var path = Path()
        if (points.count < 2){
            return path
        }
        guard let offset = globalOffset ?? points.min() else { return path }

        path.move(to: .zero)
        var p1 = CGPoint(x: 0, y: CGFloat(points[0]-offset)*step.y)
        path.addLine(to: p1)
        for pointIndex in 1..<points.count {
            let p2 = CGPoint(x: step.x * CGFloat(pointIndex), y: step.y*CGFloat(points[pointIndex]-offset))
            let midPoint = CGPoint.midPointForPoints(p1: p1, p2: p2)
            path.addQuadCurve(to: midPoint, control: CGPoint.controlPointForPoints(p1: midPoint, p2: p1))
            path.addQuadCurve(to: p2, control: CGPoint.controlPointForPoints(p1: midPoint, p2: p2))
            p1 = p2
        }
        path.addLine(to: CGPoint(x: p1.x, y: 0))
        path.closeSubpath()
        return path
    }
    
    static func linePathWithPoints(points:[Double], step:CGPoint) -> Path {
        var path = Path()
        if (points.count < 2){
            return path
        }
        guard let offset = points.min() else { return path }
        let p1 = CGPoint(x: 0, y: CGFloat(points[0]-offset)*step.y)
        path.move(to: p1)
        for pointIndex in 1..<points.count {
            let p2 = CGPoint(x: step.x * CGFloat(pointIndex), y: step.y*CGFloat(points[pointIndex]-offset))
            path.addLine(to: p2)
        }
        return path
    }
    
    static func closedLinePathWithPoints(points:[Double], step:CGPoint) -> Path {
        var path = Path()
        if (points.count < 2){
            return path
        }
        guard let offset = points.min() else { return path }
        var p1 = CGPoint(x: 0, y: CGFloat(points[0]-offset)*step.y)
        path.move(to: p1)
        for pointIndex in 1..<points.count {
            p1 = CGPoint(x: step.x * CGFloat(pointIndex), y: step.y*CGFloat(points[pointIndex]-offset))
            path.addLine(to: p1)
        }
        path.addLine(to: CGPoint(x: p1.x, y: 0))
        path.closeSubpath()
        return path
    }
}

// MARK: - CGPoint 扩展
extension CGPoint {
    func point(to: CGPoint, x: CGFloat) -> CGPoint {
        let dx = to.x - self.x
        guard dx != 0 else { return CGPoint(x: x, y: self.y) }
        let a = (to.y - self.y) / dx
        let y = self.y + (x - self.x) * a
        return CGPoint(x: x, y: y)
    }
    
    func line(to: CGPoint) -> CGFloat {
        dist(to: to)
    }
    
    func line(to: CGPoint, x: CGFloat) -> CGFloat {
        dist(to: point(to: to, x: x))
    }
    
    func quadCurve(to: CGPoint, control: CGPoint) -> CGFloat {
        var dist: CGFloat = 0
        let steps: CGFloat = 100
        
        for i in 0..<Int(steps) {
            let t0 = CGFloat(i) / steps
            let t1 = CGFloat(i+1) / steps
            let a = point(to: to, t: t0, control: control)
            let b = point(to: to, t: t1, control: control)
            
            dist += a.line(to: b)
        }
        return dist
    }
    
    func quadCurve(to: CGPoint, control: CGPoint, x: CGFloat) -> CGFloat {
        var dist: CGFloat = 0
        let steps: CGFloat = 100
        
        for i in 0..<Int(steps) {
            let t0 = CGFloat(i) / steps
            let t1 = CGFloat(i+1) / steps
            let a = point(to: to, t: t0, control: control)
            let b = point(to: to, t: t1, control: control)
            
            if a.x >= x {
                return dist
            } else if b.x > x {
                dist += a.line(to: b, x: x)
                return dist
            } else if b.x == x {
                dist += a.line(to: b)
                return dist
            }
            
            dist += a.line(to: b)
        }
        return dist
    }
    
    func point(to: CGPoint, t: CGFloat, control: CGPoint) -> CGPoint {
        let x = CGPoint.value(x: self.x, y: to.x, t: t, c: control.x)
        let y = CGPoint.value(x: self.y, y: to.y, t: t, c: control.y)
        
        return CGPoint(x: x, y: y)
    }
    
    func curve(to: CGPoint, control1: CGPoint, control2: CGPoint) -> CGFloat {
        var dist: CGFloat = 0
        let steps: CGFloat = 100
        
        for i in 0..<Int(steps) {
            let t0 = CGFloat(i) / steps
            let t1 = CGFloat(i+1) / steps
            
            let a = point(to: to, t: t0, control1: control1, control2: control2)
            let b = point(to: to, t: t1, control1: control1, control2: control2)
            
            dist += a.line(to: b)
        }
        
        return dist
    }
    
    func curve(to: CGPoint, control1: CGPoint, control2: CGPoint, x: CGFloat) -> CGFloat {
        var dist: CGFloat = 0
        let steps: CGFloat = 100
        
        for i in 0..<Int(steps) {
            let t0 = CGFloat(i) / steps
            let t1 = CGFloat(i+1) / steps
            
            let a = point(to: to, t: t0, control1: control1, control2: control2)
            let b = point(to: to, t: t1, control1: control1, control2: control2)
            
            if a.x >= x {
                return dist
            } else if b.x > x {
                dist += a.line(to: b, x: x)
                return dist
            } else if b.x == x {
                dist += a.line(to: b)
                return dist
            }
            
            dist += a.line(to: b)
        }
        
        return dist
    }
    
    func point(to: CGPoint, t: CGFloat, control1: CGPoint, control2: CGPoint) -> CGPoint {
        let x = CGPoint.value(x: self.x, y: to.x, t: t, c1: control1.x, c2: control2.x)
        let y = CGPoint.value(x: self.y, y: to.y, t: t, c1: control1.y, c2: control2.x)
        
        return CGPoint(x: x, y: y)
    }
    
    static func value(x: CGFloat, y: CGFloat, t: CGFloat, c: CGFloat) -> CGFloat {
        var value: CGFloat = 0.0
        value += pow(1-t, 2) * x
        value += 2 * (1-t) * t * c
        value += pow(t, 2) * y
        return value
    }
    
    static func value(x: CGFloat, y: CGFloat, t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
        var value: CGFloat = 0.0
        value += pow(1-t, 3) * x
        value += 3 * pow(1-t, 2) * t * c1
        value += 3 * (1-t) * pow(t, 2) * c2
        value += pow(t, 3) * y
        return value
    }
    
    static func getMidPoint(point1: CGPoint, point2: CGPoint) -> CGPoint {
        return CGPoint(
            x: point1.x + (point2.x - point1.x) / 2,
            y: point1.y + (point2.y - point1.y) / 2
        )
    }
    
    func dist(to: CGPoint) -> CGFloat {
        return sqrt((pow(self.x - to.x, 2) + pow(self.y - to.y, 2)))
    }
    
    static func midPointForPoints(p1:CGPoint, p2:CGPoint) -> CGPoint {
        return CGPoint(x:(p1.x + p2.x) / 2,y: (p1.y + p2.y) / 2)
    }
    
    static func controlPointForPoints(p1:CGPoint, p2:CGPoint) -> CGPoint {
        var controlPoint = CGPoint.midPointForPoints(p1:p1, p2:p2)
        let diffY = abs(p2.y - controlPoint.y)
        
        if (p1.y < p2.y){
            controlPoint.y += diffY
        } else if (p1.y > p2.y) {
            controlPoint.y -= diffY
        }
        return controlPoint
    }
}

// 预览

struct ScholarsGrowthLineChartView_Previews: PreviewProvider {
    static var previews: some View {
        ScholarsGrowthLineChartView()
            .environmentObject(DataManager.shared)
    }
}


