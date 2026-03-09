import Cocoa

// MARK: - Refined Chart Theme System
// Design: Desaturated scholarly palette, off-black text, tinted shadows
// Typography: SF Pro (system) with precise weight hierarchy
// Spacing: 4px rhythm (4, 8, 12, 16, 20, 24, 32, 40, 48)
enum ChartTheme: String, CaseIterable {
    case academic = "academic"
    case nature = "nature"
    case warm = "warm"
    case mono = "mono"
    case auto = "auto"

    var displayName: String {
        switch self {
        case .academic: return "Academic"
        case .nature: return "Botanical"
        case .warm: return "Amber"
        case .mono: return "Graphite"
        case .auto: return "System"
        }
    }

    var colors: ChartColorPalette {
        switch self {
        case .academic:
            return ChartColorPalette(
                primary: NSColor(hex: "#2E86C1"),
                secondary: NSColor(hex: "#5DADE2"),
                accent: NSColor(hex: "#F39C12"),
                success: NSColor(hex: "#27AE60"),
                warning: NSColor(hex: "#E67E22"),
                error: NSColor(hex: "#E74C3C"),
                background: NSColor(hex: "#F8F9FA"),
                surface: NSColor(hex: "#FFFFFF"),
                onPrimary: NSColor.white,
                onSurface: NSColor(hex: "#2C3E50"),
                gridLines: NSColor(hex: "#E8E8E8"),
                textPrimary: NSColor(hex: "#2C3E50"),
                textSecondary: NSColor(hex: "#7F8C8D"),
                border: NSColor(hex: "#DEE2E6"),
                cardBackground: NSColor(hex: "#FFFFFF"),
                shadowColor: NSColor(hex: "#2E86C1")
            )
        case .nature:
            return ChartColorPalette(
                primary: NSColor(hex: "#27AE60"),
                secondary: NSColor(hex: "#58D68D"),
                accent: NSColor(hex: "#F4D03F"),
                success: NSColor(hex: "#2ECC71"),
                warning: NSColor(hex: "#F39C12"),
                error: NSColor(hex: "#E74C3C"),
                background: NSColor(hex: "#F7F9F7"),
                surface: NSColor(hex: "#FFFFFF"),
                onPrimary: NSColor.white,
                onSurface: NSColor(hex: "#1B4F72"),
                gridLines: NSColor(hex: "#E8F5E8"),
                textPrimary: NSColor(hex: "#1B4F72"),
                textSecondary: NSColor(hex: "#5D6D5D"),
                border: NSColor(hex: "#D5E8D4"),
                cardBackground: NSColor(hex: "#FFFFFF"),
                shadowColor: NSColor(hex: "#27AE60")
            )
        case .warm:
            return ChartColorPalette(
                primary: NSColor(hex: "#E67E22"),
                secondary: NSColor(hex: "#F8C471"),
                accent: NSColor(hex: "#8E44AD"),
                success: NSColor(hex: "#27AE60"),
                warning: NSColor(hex: "#F39C12"),
                error: NSColor(hex: "#C0392B"),
                background: NSColor(hex: "#FDF6F0"),
                surface: NSColor(hex: "#FFFFFF"),
                onPrimary: NSColor.white,
                onSurface: NSColor(hex: "#922B21"),
                gridLines: NSColor(hex: "#F8E6D8"),
                textPrimary: NSColor(hex: "#922B21"),
                textSecondary: NSColor(hex: "#A04000"),
                border: NSColor(hex: "#F0D9C8"),
                cardBackground: NSColor(hex: "#FFFFFF"),
                shadowColor: NSColor(hex: "#E67E22")
            )
        case .mono:
            return ChartColorPalette(
                primary: NSColor(hex: "#2C3E50"),
                secondary: NSColor(hex: "#7F8C8D"),
                accent: NSColor(hex: "#3498DB"),
                success: NSColor(hex: "#2ECC71"),
                warning: NSColor(hex: "#F39C12"),
                error: NSColor(hex: "#E74C3C"),
                background: NSColor(hex: "#FAFAFA"),
                surface: NSColor(hex: "#FFFFFF"),
                onPrimary: NSColor.white,
                onSurface: NSColor(hex: "#2C3E50"),
                gridLines: NSColor(hex: "#E5E5E5"),
                textPrimary: NSColor(hex: "#2C3E50"),
                textSecondary: NSColor(hex: "#7F8C8D"),
                border: NSColor(hex: "#D1D1D6"),
                cardBackground: NSColor(hex: "#FFFFFF"),
                shadowColor: NSColor(hex: "#2C3E50")
            )
        case .auto:
            if NSApp.effectiveAppearance.name == .darkAqua {
                return darkTheme
            } else {
                return lightTheme
            }
        }
    }

    private var lightTheme: ChartColorPalette {
        return ChartColorPalette(
            primary: NSColor.systemBlue,
            secondary: NSColor.systemTeal,
            accent: NSColor.systemOrange,
            success: NSColor.systemGreen,
            warning: NSColor.systemYellow,
            error: NSColor.systemRed,
            background: NSColor.controlBackgroundColor,
            surface: NSColor.controlBackgroundColor,
            onPrimary: NSColor.white,
            onSurface: NSColor.labelColor,
            gridLines: NSColor.separatorColor,
            textPrimary: NSColor.labelColor,
            textSecondary: NSColor.secondaryLabelColor,
            border: NSColor.separatorColor,
            cardBackground: NSColor.controlBackgroundColor,
            shadowColor: NSColor.systemBlue
        )
    }

    private var darkTheme: ChartColorPalette {
        return ChartColorPalette(
            primary: NSColor.systemBlue,
            secondary: NSColor.systemTeal,
            accent: NSColor.systemOrange,
            success: NSColor.systemGreen,
            warning: NSColor.systemYellow,
            error: NSColor.systemRed,
            background: NSColor.controlBackgroundColor,
            surface: NSColor.controlBackgroundColor,
            onPrimary: NSColor.white,
            onSurface: NSColor.labelColor,
            gridLines: NSColor.separatorColor,
            textPrimary: NSColor.labelColor,
            textSecondary: NSColor.secondaryLabelColor,
            border: NSColor.separatorColor,
            cardBackground: NSColor.controlBackgroundColor,
            shadowColor: NSColor.black
        )
    }
}

// MARK: - Color Palette Structure
struct ChartColorPalette {
    let primary: NSColor
    let secondary: NSColor
    let accent: NSColor
    let success: NSColor
    let warning: NSColor
    let error: NSColor
    let background: NSColor
    let surface: NSColor
    let onPrimary: NSColor
    let onSurface: NSColor
    let gridLines: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let border: NSColor
    let cardBackground: NSColor
    let shadowColor: NSColor

    // Chart-specific gradients
    var primaryGradient: [NSColor] {
        return [primary, primary.withAlphaComponent(0.6)]
    }

    var chartDataColors: [NSColor] {
        return [primary, secondary, accent, success, warning]
    }
}

// MARK: - NSColor Hex Extension
extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}

// MARK: - Chart Style Configuration
struct ChartStyleConfig {
    let theme: ChartTheme
    let animationDuration: TimeInterval
    let cornerRadius: CGFloat
    let shadowOpacity: Float
    let fontSizes: FontSizes

    static let `default` = ChartStyleConfig(
        theme: .academic,
        animationDuration: 0.25,
        cornerRadius: 10.0,
        shadowOpacity: 0.06,
        fontSizes: FontSizes()
    )
}

// MARK: - Typography Scale (4px rhythm)
// Display: 28pt semibold — section headers
// Title:   18pt semibold — card titles
// Body:    13pt regular — primary content
// Caption: 11pt regular — secondary labels
// Mono:    11pt monospaced — numeric data
struct FontSizes {
    let display: CGFloat = 28
    let title: CGFloat = 18
    let subtitle: CGFloat = 14
    let body: CGFloat = 13
    let caption: CGFloat = 11
    let chartLabel: CGFloat = 10
}

// MARK: - Spacing Constants (4px rhythm)
struct DesignSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let section: CGFloat = 48

    // Card-specific
    static let cardPadding: CGFloat = 20
    static let cardCornerRadius: CGFloat = 10
    static let cardShadowRadius: CGFloat = 12
    static let cardShadowOpacity: Float = 0.06

    // Toolbar
    static let toolbarHeight: CGFloat = 52
    static let toolbarPadding: CGFloat = 16
}
