import Foundation

// MARK: - Analytics Event Names
// All Firebase Analytics event names, organized by category.
// Firebase event names must be <= 40 chars, snake_case, no spaces.

enum AnalyticsEventName {

    // MARK: - App Lifecycle
    static let appOpen = "app_open"
    static let appFirstLaunch = "app_first_launch"
    static let appForeground = "app_foreground"
    static let appBackground = "app_background"
    static let appTerminate = "app_terminate"
    static let bgRefreshTriggered = "bg_refresh_triggered"
    static let bgRefreshCompleted = "bg_refresh_completed"

    // MARK: - Navigation
    static let tabSelected = "tab_selected"
    static let settingsTabChanged = "settings_tab_changed"
    static let deepLinkOpened = "deep_link_opened"
    static let screenView = "screen_view"

    // MARK: - Scholar Management
    static let scholarAddSheetOpened = "scholar_add_sheet_opened"
    static let scholarAddSubmitted = "scholar_add_submitted"
    static let scholarAddSuccess = "scholar_add_success"
    static let scholarAddError = "scholar_add_error"
    static let scholarDelete = "scholar_delete"
    static let scholarDeleteAll = "scholar_delete_all"
    static let scholarEditOpened = "scholar_edit_opened"
    static let scholarEditSaved = "scholar_edit_saved"
    static let scholarPinToggled = "scholar_pin_toggled"
    static let scholarMarkedAsMe = "scholar_marked_as_me"
    static let scholarReordered = "scholar_reordered"
    static let scholarCameraScanStarted = "scholar_camera_scan_started"
    static let scholarCameraScanSuccess = "scholar_camera_scan_success"
    static let scholarCameraScanCancelled = "scholar_camera_scan_cancel"

    // MARK: - Citation Refresh
    static let citationRefreshManual = "citation_refresh_manual"
    static let citationRefreshAuto = "citation_refresh_auto"
    static let citationRefreshBgTask = "citation_refresh_bg_task"
    static let citationRefreshWidget = "citation_refresh_widget"
    static let citationRefreshSuccess = "citation_refresh_success"
    static let citationRefreshError = "citation_refresh_error"
    static let citationChangeDetected = "citation_change_detected"
    static let citationGrowthCelebrated = "citation_growth_celebrated"
    static let citationRefreshCompleted = "citation_refresh_completed"

    // MARK: - Dashboard (iOS)
    static let dashboardSortChanged = "dashboard_sort_changed"
    static let dashboardSwipeSort = "dashboard_swipe_sort"
    static let dashboardScholarChartOpened = "dashboard_scholar_chart_open"
    static let dashboardChartTimeRangeChanged = "dashboard_chart_range_changed"
    static let dashboardChartDataPointSelected = "dashboard_chart_point_select"

    // MARK: - Who Cited Me (iOS)
    static let whoCitedMeScholarSelected = "who_cited_scholar_selected"
    static let whoCitedMePublicationExpanded = "who_cited_pub_expanded"
    static let whoCitedMeSortChanged = "who_cited_sort_changed"
    static let whoCitedMeLoadMore = "who_cited_load_more"
    static let citingPaperDetailOpened = "citing_paper_detail_opened"
    static let citingPaperScholarLinkTapped = "citing_paper_scholar_link"
    static let citingPaperPdfTapped = "citing_paper_pdf_tapped"
    static let citationFilterOpened = "citation_filter_opened"
    static let citationFilterApplied = "citation_filter_applied"
    static let citationFilterCleared = "citation_filter_cleared"
    static let citationExportStarted = "citation_export_started"
    static let citationExportShared = "citation_export_shared"
    static let citationBadgeTapped = "citation_badge_tapped"
    static let citationStatisticsViewed = "citation_statistics_viewed"

    // MARK: - Charts
    static let chartsScholarSelected = "charts_scholar_selected"
    static let chartsTimeRangeChanged = "charts_time_range_changed"
    static let chartsCustomRangeApplied = "charts_custom_range_applied"
    static let chartsChartTypeChanged = "charts_chart_type_changed"
    static let chartsThemeChanged = "charts_theme_changed"
    static let chartsDataPointHovered = "charts_data_point_hovered"
    static let chartsDataPointClicked = "charts_data_point_clicked"
    static let chartsRefresh = "charts_refresh"
    static let chartsExport = "charts_export"
    static let chartsDataManagementOpened = "charts_data_mgmt_opened"
    static let heatmapCellTapped = "heatmap_cell_tapped"
    static let heatmapCellLongPressed = "heatmap_cell_long_pressed"

    // MARK: - Settings
    static let settingsLanguageChanged = "settings_language_changed"
    static let settingsThemeChanged = "settings_theme_changed"
    static let settingsWidgetThemeChanged = "settings_widget_theme_changed"
    static let settingsAutoUpdateToggled = "settings_auto_update_toggled"
    static let settingsAutoUpdateFreqChanged = "settings_update_freq_changed"
    static let settingsICloudSyncToggled = "settings_icloud_sync_toggled"
    static let settingsICloudSyncNow = "settings_icloud_sync_now"
    static let settingsShowInDockChanged = "settings_show_dock_changed"
    static let settingsShowInMenuBarChanged = "settings_show_menubar_changed"
    static let settingsLaunchAtLoginChanged = "settings_launch_login_changed"
    static let settingsDataImportStarted = "settings_data_import_started"
    static let settingsDataImportSuccess = "settings_data_import_success"
    static let settingsDataImportError = "settings_data_import_error"
    static let settingsDataExportStarted = "settings_data_export_started"
    static let settingsCacheCleared = "settings_cache_cleared"
    static let settingsNotificationsPermission = "settings_notif_permission"

    // MARK: - Data Management (macOS)
    static let dataEntryEdited = "data_entry_edited"
    static let dataEntriesDeleted = "data_entries_deleted"
    static let dataRestoredToPoint = "data_restored_to_point"
    static let dataRefreshFromPoint = "data_refresh_from_point"
    static let dataExported = "data_exported"

    // MARK: - Notifications (macOS)
    static let notificationSent = "notification_sent"
    static let notificationBatchSent = "notification_batch_sent"
    static let notificationChartsClicked = "notification_charts_clicked"
    static let notificationSettingsChanged = "notification_settings_changed"

    // MARK: - Widget (iOS)
    static let widgetRefreshTriggered = "widget_refresh_triggered"
    static let widgetScholarSwitched = "widget_scholar_switched"
    static let widgetScholarSelected = "widget_scholar_selected"
    static let widgetDeepLinkOpened = "widget_deep_link_opened"

    // MARK: - Errors
    static let coreDataError = "core_data_error"
    static let networkError = "network_error"
    static let rateLimitHit = "rate_limit_hit"
    static let parseError = "parse_error"
    static let icloudSyncError = "icloud_sync_error"
}

// MARK: - Analytics Parameter Keys
enum AnalyticsParamKey {
    // Common
    static let platform = "platform"
    static let scholarCount = "scholar_count"
    static let success = "success"
    static let errorType = "error_type"
    static let format = "format"

    // Navigation
    static let tabName = "tab_name"
    static let screenName = "screen_name"
    static let screenClass = "screen_class"
    static let host = "host"
    static let source = "source"

    // Scholar
    static let inputType = "input_type"
    static let citationCount = "citation_count"
    static let hIndex = "h_index"
    static let scholarCountAfter = "scholar_count_after"
    static let action = "action"
    static let method = "method"

    // Citation Refresh
    static let newTotal = "new_total"
    static let delta = "delta"
    static let direction = "direction"
    static let successCount = "success_count"
    static let failCount = "fail_count"
    static let durationMs = "duration_ms"
    static let statusCode = "status_code"

    // Dashboard
    static let sortType = "sort_type"
    static let sortBy = "sort_by"
    static let range = "range"

    // Who Cited Me
    static let citingPaperCount = "citing_paper_count"
    static let currentCount = "current_count"
    static let hasAbstract = "has_abstract"
    static let hasYearRange = "has_year_range"
    static let hasKeyword = "has_keyword"
    static let hasAuthor = "has_author"
    static let badgeCount = "badge_count"
    static let totalCitingPapers = "total_citing_papers"

    // Charts
    static let chartType = "chart_type"
    static let theme = "theme"
    static let daysSpan = "days_span"

    // Settings
    static let newLanguage = "new_language"
    static let oldLanguage = "old_language"
    static let newTheme = "new_theme"
    static let enabled = "enabled"
    static let frequencyHours = "frequency_hours"
    static let granted = "granted"

    // Notifications
    static let type = "type"
    static let count = "count"

    // Data Management
    static let operation = "operation"

    // App Info
    static let appVersion = "app_version"
}

// MARK: - Analytics User Property Names
enum AnalyticsUserProperty {
    static let scholarCount = "scholar_count"
    static let appLanguage = "app_language"
    static let appTheme = "app_theme"
    static let updateInterval = "update_interval"
    static let icloudSyncEnabled = "icloud_sync_enabled"
    static let autoUpdateEnabled = "auto_update_enabled"
    static let platform = "platform"
    static let appVersion = "app_version"
    #if os(macOS)
    static let launchAtLogin = "launch_at_login"
    static let showInDock = "show_in_dock"
    #endif
}

// MARK: - Screen Names
enum AnalyticsScreen {
    // iOS Screens
    static let dashboard = "Dashboard"
    static let scholars = "Scholars"
    static let charts = "Charts"
    static let whoCiteMe = "WhoCiteMe"
    static let settings = "Settings"
    static let addScholar = "AddScholar"
    static let editScholar = "EditScholar"
    static let cameraScanner = "CameraScanner"
    static let themeSelection = "ThemeSelection"
    static let languageSelection = "LanguageSelection"
    static let widgetThemeSelection = "WidgetThemeSelection"
    static let autoUpdateSettings = "AutoUpdateSettings"
    static let citingPaperDetail = "CitingPaperDetail"
    static let citationStatistics = "CitationStatistics"
    static let citationFilter = "CitationFilter"

    // macOS Screens
    static let settingsWindow = "SettingsWindow"
    static let chartsWindow = "ChartsWindow"
    static let dataRepairWindow = "DataRepairWindow"
    static let aboutWindow = "AboutWindow"
}

// MARK: - Tab Names
enum AnalyticsTabName {
    static let dashboard = "dashboard"
    static let scholars = "scholars"
    static let charts = "charts"
    static let whoCiteMe = "who_cited_me"
    static let insights = "citation_insights"
    static let settings = "settings"

    // Tab layout (5 tabs): Who-Cite-Me is no longer a standalone tab — its
    // functionality lives inside the Scholars tab (tap a scholar to drill in).
    static func from(index: Int) -> String {
        switch index {
        case 0: return dashboard
        case 1: return scholars
        case 2: return charts
        case 3: return insights
        case 4: return settings
        default: return "unknown_\(index)"
        }
    }
}
