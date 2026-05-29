import SwiftUI

// MARK: - Theme Selection View
struct ThemeSelectionView: View {
    @StateObject private var localizationManager = LocalizationManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                HStack(spacing: 12) {
                    Image(systemName: theme == .light ? "sun.max.fill" : theme == .dark ? "moon.fill" : "gear")
                        .font(.title2)
                        .foregroundColor(theme == .light ? .orange : theme == .dark ? .purple : .blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizationManager.localized(theme == .light ? "light_mode" : theme == .dark ? "dark_mode" : "system_mode"))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    if settingsManager.theme == theme {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    AnalyticsService.shared.log(AnalyticsEventName.settingsThemeChanged, parameters: [
                        AnalyticsParamKey.newTheme: theme.rawValue
                    ])
                    AnalyticsService.shared.setUserProperty(theme.rawValue, forName: AnalyticsUserProperty.appTheme)
                    settingsManager.theme = theme
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dismiss()
                    }
                }
            }
        }
        .liquidGlassCanvas()
        .navigationTitle(localizationManager.localized("theme"))
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen(AnalyticsScreen.themeSelection)
    }
}

// MARK: - Widget Theme Selection View
struct WidgetThemeSelectionView: View {
    @StateObject private var localizationManager = LocalizationManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                HStack(spacing: 12) {
                    Image(systemName: theme == .light ? "sun.max.fill" : theme == .dark ? "moon.fill" : "gear")
                        .font(.title2)
                        .foregroundColor(theme == .light ? .orange : theme == .dark ? .purple : .blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizationManager.localized(theme == .light ? "light_mode" : theme == .dark ? "dark_mode" : "system_mode"))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    if settingsManager.widgetTheme == theme {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    AnalyticsService.shared.log(AnalyticsEventName.settingsWidgetThemeChanged, parameters: [
                        AnalyticsParamKey.newTheme: theme.rawValue
                    ])
                    settingsManager.widgetTheme = theme
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dismiss()
                    }
                }
            }
        }
        .liquidGlassCanvas()
        .navigationTitle(localizationManager.localized("widget_theme"))
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen(AnalyticsScreen.widgetThemeSelection)
    }
}

// MARK: - Language Selection View
struct LanguageSelectionView: View {
    @StateObject private var localizationManager = LocalizationManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(LocalizationManager.Language.allCases, id: \.self) { language in
                HStack(spacing: 12) {
                    Text(language.flag)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.nativeName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(language.displayName.replacingOccurrences(of: language.flag, with: "").trimmingCharacters(in: .whitespaces))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if localizationManager.currentLanguage == language {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    let oldLanguage = localizationManager.currentLanguage.rawValue
                    AnalyticsService.shared.log(AnalyticsEventName.settingsLanguageChanged, parameters: [
                        AnalyticsParamKey.newLanguage: language.rawValue,
                        AnalyticsParamKey.oldLanguage: oldLanguage
                    ])
                    AnalyticsService.shared.setUserProperty(language.rawValue, forName: AnalyticsUserProperty.appLanguage)
                    localizationManager.switchLanguage(to: language) {
                        dismiss()
                    }
                }
            }
        }
        .liquidGlassCanvas()
        .navigationTitle(localizationManager.localized("select_language"))
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen(AnalyticsScreen.languageSelection)
    }
}
