import SwiftUI
import CoreFoundation
// 导入共享常量
let appGroupIdentifier: String = "group.com.citetrack.CiteTrack"

// 发送跨进程 Darwin 通知，通知主App从 App Group 拉取最新时间
private func postDarwinNotification(_ name: String) {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    print("🧪 [Widget] 已发送 Darwin 通知: \(name)")
}
import WidgetKit
import AppIntents

// MARK: - Widget Localization Helper
class WidgetLocalization {
    static let shared = WidgetLocalization()
    
    private init() {}
    
    func localized(_ key: String) -> String {
        // Simple localization for widget extension
        // This uses the system language to determine the appropriate translation
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        
        switch language {
        case "zh":
            return chineseLocalizations[key] ?? key
        case "ja":
            return japaneseLocalizations[key] ?? key
        case "ko":
            return koreanLocalizations[key] ?? key
        case "es":
            return spanishLocalizations[key] ?? key
        case "fr":
            return frenchLocalizations[key] ?? key
        case "de":
            return germanLocalizations[key] ?? key
        default:
            return englishLocalizations[key] ?? key
        }
    }
    
    private let englishLocalizations: [String: String] = [
        "citations_label": "Citations",
        "start_tracking": "Start Tracking",
        "add_scholar_to_track": "Add Scholar to Track",
        "tap_to_open_app": "Tap to Open App",
        "academic_influence": "Academic Influence",
        "top_scholars": "Top Scholars",
        "total_citations_label": "Total Citations",
        "updated_at": "Updated at",
        "academic_ranking": "Academic Ranking",
        "add_scholars_to_track": "Add Scholars to Track",
        "tracking_scholars": "Tracking Scholars",
        "latest_data": "Latest Data",
        "average_citations_label": "Average Citations",
        "highest_citations_label": "Highest Citations",
        "this_month": "This Month",
        "data_insights": "Data Insights",
        "select_scholar": "Select Scholar",
        "select_scholar_description": "Select a scholar to display in the widget",
        "scholar_parameter": "Scholar",
        "scholar_parameter_description": "Select the scholar to display in the small widget",
        "force_refresh_widget": "Force Refresh Widget",
        "force_refresh_description": "Force refresh widget data",
        "debug_test": "Debug Test",
        "debug_test_description": "Debug test intent",
        "refresh_data": "Refresh Data",
        "refresh_data_description": "Refresh scholar citation data",
        "switch_scholar": "Switch Scholar",
        "switch_scholar_description": "Switch to next scholar",
        "citations_unit": "citations",
        "no_data_available": "No Data Available",
        "scholar_default_name": "Scholar",
        "icloud_available_no_sync": "Not Synced",
        "export_failed_with_message": "Export failed",
        "import_failed_with_message": "Import failed",
        "failed_with_colon": "Failed",
        "dashboard": "Dashboard"
    ]
    
    private let chineseLocalizations: [String: String] = [
        "citations_label": "引用数",
        "start_tracking": "开始追踪",
        "add_scholar_to_track": "添加学者开始追踪",
        "tap_to_open_app": "轻触打开App添加学者",
        "academic_influence": "学术影响力",
        "top_scholars": "学者",
        "total_citations_label": "总引用",
        "updated_at": "更新于",
        "academic_ranking": "学术排行榜",
        "add_scholars_to_track": "添加学者开始追踪\n他们的学术影响力",
        "tracking_scholars": "追踪学者",
        "latest_data": "最新数据",
        "average_citations_label": "平均引用",
        "highest_citations_label": "最高引用",
        "this_month": "本月",
        "data_insights": "数据洞察",
        "select_scholar": "选择学者",
        "select_scholar_description": "从已添加的学者中选择要显示的学者",
        "scholar_parameter": "学者",
        "scholar_parameter_description": "选择要在小组件中显示的学者",
        "force_refresh_widget": "强制刷新小组件",
        "force_refresh_description": "强制刷新小组件数据",
        "debug_test": "调试测试",
        "debug_test_description": "调试用的测试Intent",
        "refresh_data": "刷新数据",
        "refresh_data_description": "刷新学者的引用数据",
        "switch_scholar": "切换学者",
        "switch_scholar_description": "切换到下一个学者",
        "citations_unit": "引用",
        "no_data_available": "暂无数据",
        "scholar_default_name": "学者",
        "icloud_available_no_sync": "未同步",
        "export_failed_with_message": "导出失败",
        "import_failed_with_message": "导入失败",
        "failed_with_colon": "失败",
        "dashboard": "仪表板"
    ]
    
    private let japaneseLocalizations: [String: String] = [
        "citations_label": "引用数",
        "start_tracking": "追跡開始",
        "add_scholar_to_track": "研究者を追加して追跡開始",
        "tap_to_open_app": "アプリをタップして研究者を追加",
        "academic_influence": "学術的影響力",
        "top_scholars": "研究者",
        "total_citations_label": "総引用数",
        "updated_at": "更新日時",
        "academic_ranking": "学術ランキング",
        "add_scholars_to_track": "研究者を追加して追跡開始\n彼らの学術的影響力",
        "tracking_scholars": "研究者を追跡中",
        "latest_data": "最新データ",
        "average_citations_label": "平均引用数",
        "highest_citations_label": "最高引用数",
        "this_month": "今月",
        "data_insights": "データインサイト",
        "select_scholar": "研究者を選択",
        "select_scholar_description": "ウィジェットに表示する研究者を選択",
        "scholar_parameter": "研究者",
        "scholar_parameter_description": "小さなウィジェットに表示する研究者を選択",
        "force_refresh_widget": "ウィジェットを強制更新",
        "force_refresh_description": "ウィジェットデータを強制更新",
        "debug_test": "デバッグテスト",
        "debug_test_description": "デバッグ用テストIntent",
        "refresh_data": "データを更新",
        "refresh_data_description": "研究者の引用データを更新",
        "switch_scholar": "研究者を切り替え",
        "switch_scholar_description": "次の研究者に切り替え",
        "citations_unit": "引用",
        "no_data_available": "データなし",
        "scholar_default_name": "研究者",
        "icloud_available_no_sync": "未同期",
        "export_failed_with_message": "エクスポート失敗",
        "import_failed_with_message": "インポート失敗",
        "failed_with_colon": "失敗",
        "dashboard": "ダッシュボード"
    ]
    
    private let koreanLocalizations: [String: String] = [
        "citations_label": "인용수",
        "start_tracking": "추적 시작",
        "add_scholar_to_track": "학자를 추가하여 추적 시작",
        "tap_to_open_app": "앱을 탭하여 학자 추가",
        "academic_influence": "학술적 영향력",
        "top_scholars": "학자",
        "total_citations_label": "총 인용수",
        "updated_at": "업데이트 시간",
        "academic_ranking": "학술 순위",
        "add_scholars_to_track": "학자를 추가하여 추적 시작\n그들의 학술적 영향력",
        "tracking_scholars": "학자 추적 중",
        "latest_data": "최신 데이터",
        "average_citations_label": "평균 인용수",
        "highest_citations_label": "최고 인용수",
        "this_month": "이번 달",
        "data_insights": "데이터 인사이트",
        "select_scholar": "학자 선택",
        "select_scholar_description": "위젯에 표시할 학자 선택",
        "scholar_parameter": "학자",
        "scholar_parameter_description": "작은 위젯에 표시할 학자 선택",
        "force_refresh_widget": "위젯 강제 새로고침",
        "force_refresh_description": "위젯 데이터 강제 새로고침",
        "debug_test": "디버그 테스트",
        "debug_test_description": "디버그용 테스트 Intent",
        "refresh_data": "데이터 새로고침",
        "refresh_data_description": "학자 인용 데이터 새로고침",
        "switch_scholar": "학자 전환",
        "switch_scholar_description": "다음 학자로 전환",
        "citations_unit": "인용",
        "no_data_available": "데이터 없음",
        "scholar_default_name": "학자",
        "icloud_available_no_sync": "동기화 안됨",
        "export_failed_with_message": "내보내기 실패",
        "import_failed_with_message": "가져오기 실패",
        "failed_with_colon": "실패",
        "dashboard": "대시보드"
    ]
    
    private let spanishLocalizations: [String: String] = [
        "citations_label": "Citas",
        "start_tracking": "Iniciar Seguimiento",
        "add_scholar_to_track": "Agregar Académico para Seguir",
        "tap_to_open_app": "Toca para Abrir App y Agregar Académico",
        "academic_influence": "Influencia Académica",
        "top_scholars": "Académicos",
        "total_citations_label": "Total de Citas",
        "updated_at": "Actualizado en",
        "academic_ranking": "Ranking Académico",
        "add_scholars_to_track": "Agregar Académicos para Seguir\nSu Influencia Académica",
        "tracking_scholars": "Siguiendo Académicos",
        "latest_data": "Datos Más Recientes",
        "average_citations_label": "Promedio de Citas",
        "highest_citations_label": "Mayor Número de Citas",
        "this_month": "Este Mes",
        "data_insights": "Perspectivas de Datos",
        "select_scholar": "Seleccionar Académico",
        "select_scholar_description": "Selecciona un académico para mostrar en el widget",
        "scholar_parameter": "Académico",
        "scholar_parameter_description": "Selecciona el académico para mostrar en el widget pequeño",
        "force_refresh_widget": "Forzar Actualización del Widget",
        "force_refresh_description": "Forzar actualización de datos del widget",
        "debug_test": "Prueba de Depuración",
        "debug_test_description": "Intent de prueba para depuración",
        "refresh_data": "Actualizar Datos",
        "refresh_data_description": "Actualizar datos de citas del académico",
        "switch_scholar": "Cambiar Académico",
        "switch_scholar_description": "Cambiar al siguiente académico",
        "citations_unit": "citas",
        "no_data_available": "Sin Datos Disponibles",
        "scholar_default_name": "Académico",
        "icloud_available_no_sync": "No Sincronizado",
        "export_failed_with_message": "Exportación fallida",
        "import_failed_with_message": "Importación fallida",
        "failed_with_colon": "Fallida",
        "dashboard": "Panel de Control"
    ]
    
    private let frenchLocalizations: [String: String] = [
        "citations_label": "Citations",
        "start_tracking": "Commencer le Suivi",
        "add_scholar_to_track": "Ajouter un Chercheur à Suivre",
        "tap_to_open_app": "Touchez pour Ouvrir l'App et Ajouter un Chercheur",
        "academic_influence": "Influence Académique",
        "top_scholars": "Chercheurs",
        "total_citations_label": "Total des Citations",
        "updated_at": "Mis à jour le",
        "academic_ranking": "Classement Académique",
        "add_scholars_to_track": "Ajouter des Chercheurs à Suivre\nLeur Influence Académique",
        "tracking_scholars": "Suivi des Chercheurs",
        "latest_data": "Dernières Données",
        "average_citations_label": "Moyenne des Citations",
        "highest_citations_label": "Plus Grand Nombre de Citations",
        "this_month": "Ce Mois",
        "data_insights": "Perspectives de Données",
        "select_scholar": "Sélectionner un Chercheur",
        "select_scholar_description": "Sélectionnez un chercheur à afficher dans le widget",
        "scholar_parameter": "Chercheur",
        "scholar_parameter_description": "Sélectionnez le chercheur à afficher dans le petit widget",
        "force_refresh_widget": "Forcer la Mise à Jour du Widget",
        "force_refresh_description": "Forcer la mise à jour des données du widget",
        "debug_test": "Test de Débogage",
        "debug_test_description": "Intent de test pour le débogage",
        "refresh_data": "Actualiser les Données",
        "refresh_data_description": "Actualiser les données de citations du chercheur",
        "switch_scholar": "Changer de Chercheur",
        "switch_scholar_description": "Passer au chercheur suivant",
        "citations_unit": "citations",
        "no_data_available": "Aucune Donnée Disponible",
        "scholar_default_name": "Chercheur",
        "icloud_available_no_sync": "Non Synchronisé",
        "export_failed_with_message": "Exportation échouée",
        "import_failed_with_message": "Importation échouée",
        "failed_with_colon": "Échouée",
        "dashboard": "Tableau de Bord"
    ]
    
    private let germanLocalizations: [String: String] = [
        "citations_label": "Zitationen",
        "start_tracking": "Verfolgung Starten",
        "add_scholar_to_track": "Forscher Hinzufügen zum Verfolgen",
        "tap_to_open_app": "Tippen um App zu Öffnen und Forscher Hinzuzufügen",
        "academic_influence": "Akademischer Einfluss",
        "top_scholars": "Forscher",
        "total_citations_label": "Gesamtzitationen",
        "updated_at": "Aktualisiert am",
        "academic_ranking": "Akademisches Ranking",
        "add_scholars_to_track": "Forscher Hinzufügen zum Verfolgen\nIhr Akademischer Einfluss",
        "tracking_scholars": "Forscher Verfolgen",
        "latest_data": "Neueste Daten",
        "average_citations_label": "Durchschnittliche Zitationen",
        "highest_citations_label": "Höchste Zitationen",
        "this_month": "Diesen Monat",
        "data_insights": "Daten-Einblicke",
        "select_scholar": "Forscher Auswählen",
        "select_scholar_description": "Wählen Sie einen Forscher aus, der im Widget angezeigt werden soll",
        "scholar_parameter": "Forscher",
        "scholar_parameter_description": "Wählen Sie den Forscher aus, der im kleinen Widget angezeigt werden soll",
        "force_refresh_widget": "Widget Erzwingen Aktualisieren",
        "force_refresh_description": "Widget-Daten erzwingen aktualisieren",
        "debug_test": "Debug-Test",
        "debug_test_description": "Test-Intent für Debugging",
        "refresh_data": "Daten Aktualisieren",
        "refresh_data_description": "Forscher-Zitationsdaten aktualisieren",
        "switch_scholar": "Forscher Wechseln",
        "switch_scholar_description": "Zum nächsten Forscher wechseln",
        "citations_unit": "Zitationen",
        "no_data_available": "Keine Daten Verfügbar",
        "scholar_default_name": "Forscher",
        "icloud_available_no_sync": "Nicht Synchronisiert",
        "export_failed_with_message": "Export fehlgeschlagen",
        "import_failed_with_message": "Import fehlgeschlagen",
        "failed_with_colon": "Fehlgeschlagen",
        "dashboard": "Dashboard"
    ]
}

// MARK: - String Extension for Widget
extension String {
    var widgetLocalized: String {
        return WidgetLocalization.shared.localized(self)
    }
}
import os.log

// 导入共享模块
import Foundation

// MARK: - 背景色助手（根据 WidgetTheme 显式给出颜色）
@inline(__always)
fileprivate func widgetBackgroundColor(for theme: WidgetTheme) -> Color {
    switch theme {
    case .light:
        return Color.white
    case .dark:
        return Color.black
    case .system:
        // 跟随系统时交给系统材质，由容器或系统决定
        return .clear
    }
}

// MARK: - Widget专用数据服务 (内联版本)
/// 避免Xcode项目配置问题，直接在Widget文件中定义
class WidgetDataService {
    static let shared = WidgetDataService()
    
    private init() {}
    
    func getWidgetData() async throws -> WidgetData {
        // 优先从App Group读取
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        // 🎯 使用DataManager已计算好的Widget数据，而不是重新计算
        var scholars: [WidgetScholarInfo] = []
        
        // 优先从App Group读取已计算好的WidgetScholars数据
        if let appGroupDefaults = appGroupDefaults,
           let data = appGroupDefaults.data(forKey: "WidgetScholars"),
           let decodedScholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
            scholars = decodedScholars
            print("✅ [WidgetDataService] 从App Group加载了 \(scholars.count) 位学者的已计算数据")
        } else if let data = standardDefaults.data(forKey: "WidgetScholars"),
                  let decodedScholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
            scholars = decodedScholars
            print("✅ [WidgetDataService] 从标准存储加载了 \(scholars.count) 位学者的已计算数据")
        } else {
            // 🚨 后备方案：如果没有WidgetScholars数据，读取原始数据（但不重新计算变化）
            print("⚠️ [WidgetDataService] 未找到WidgetScholars数据，使用原始ScholarsList")
            if let appGroupDefaults = appGroupDefaults,
               let data = appGroupDefaults.data(forKey: "ScholarsList"),
               let decodedScholars = try? JSONDecoder().decode([SimpleScholar].self, from: data) {
                scholars = decodedScholars.map { scholar in
                    WidgetScholarInfo(
                        id: scholar.id,
                        displayName: scholar.name,
                        institution: nil,
                        citations: scholar.citations,
                        hIndex: nil,
                        lastUpdated: scholar.lastUpdated,
                        monthlyGrowth: nil  // 不在Widget中计算，等待主应用提供
                    )
                }
            } else if let data = standardDefaults.data(forKey: "ScholarsList"),
                      let decodedScholars = try? JSONDecoder().decode([SimpleScholar].self, from: data) {
                scholars = decodedScholars.map { scholar in
                    WidgetScholarInfo(
                        id: scholar.id,
                        displayName: scholar.name,
                        institution: nil,
                        citations: scholar.citations,
                        hIndex: nil,
                        lastUpdated: scholar.lastUpdated,
                        monthlyGrowth: nil  // 不在Widget中计算，等待主应用提供
                    )
                }
            }
        }
        
        // 获取选中的学者ID
        let selectedScholarId = appGroupDefaults?.string(forKey: "SelectedWidgetScholarId") ??
                               standardDefaults.string(forKey: "SelectedWidgetScholarId")
        
        // 计算总引用数
        let totalCitations = scholars.reduce(0) { $0 + ($1.citations ?? 0) }
        
        // 获取最后更新时间
        let lastUpdateTime = appGroupDefaults?.object(forKey: "LastRefreshTime") as? Date ??
                            standardDefaults.object(forKey: "LastRefreshTime") as? Date
        
        return WidgetData(
            scholars: scholars,
            selectedScholarId: selectedScholarId,
            totalCitations: totalCitations,
            lastUpdateTime: lastUpdateTime
        )
    }
    
    func recordRefreshAction() async {
        let now = Date()
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        standardDefaults.set(now, forKey: "LastRefreshTime")
        standardDefaults.set(now, forKey: "RefreshTriggerTime")
        standardDefaults.set(true, forKey: "RefreshTriggered")
        
        appGroupDefaults?.set(now, forKey: "LastRefreshTime")
        appGroupDefaults?.set(now, forKey: "RefreshTriggerTime")
        appGroupDefaults?.set(true, forKey: "RefreshTriggered")
        appGroupDefaults?.synchronize()
    }
    
    func recordScholarSwitchAction() async {
        let now = Date()
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        standardDefaults.set(now, forKey: "LastScholarSwitchTime")
        standardDefaults.set(true, forKey: "ScholarSwitched")
        
        appGroupDefaults?.set(now, forKey: "LastScholarSwitchTime")
        appGroupDefaults?.set(true, forKey: "ScholarSwitched")
        appGroupDefaults?.synchronize()
    }
    
    // ✅ 已移除calculateMonthlyGrowth函数 - Widget不再负责计算，只负责显示DataManager计算好的数据
    
    func switchToNextScholar() async throws {
        let data = try await getWidgetData()
        
        guard !data.scholars.isEmpty else {
            return
        }
        
        let currentIndex: Int
        if let selectedId = data.selectedScholarId,
           let index = data.scholars.firstIndex(where: { $0.id == selectedId }) {
            currentIndex = index
        } else {
            currentIndex = -1
        }
        
        let nextIndex = (currentIndex + 1) % data.scholars.count
        let nextScholar = data.scholars[nextIndex]
        
        // 更新选中的学者
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier)
        let standardDefaults = UserDefaults.standard
        
        standardDefaults.set(nextScholar.id, forKey: "SelectedWidgetScholarId")
        standardDefaults.set(nextScholar.displayName, forKey: "SelectedWidgetScholarName")
        
        appGroupDefaults?.set(nextScholar.id, forKey: "SelectedWidgetScholarId")
        appGroupDefaults?.set(nextScholar.displayName, forKey: "SelectedWidgetScholarName")
        appGroupDefaults?.synchronize()
        
        await recordScholarSwitchAction()
    }
}

// 简化的Scholar模型用于解码
private struct SimpleScholar: Codable {
    let id: String
    let name: String
    let citations: Int?
    let lastUpdated: Date?
}

// (已移除) Widget侧 Simple 历史持久化与增长计算，历史统一由数据层维护

// Widget数据结构 (内联定义)
struct WidgetData: Codable {
    let scholars: [WidgetScholarInfo]
    let selectedScholarId: String?
    let totalCitations: Int
    let lastUpdateTime: Date?
    
    init(scholars: [WidgetScholarInfo], selectedScholarId: String?, totalCitations: Int, lastUpdateTime: Date?) {
        self.scholars = scholars
        self.selectedScholarId = selectedScholarId
        self.totalCitations = totalCitations
        self.lastUpdateTime = lastUpdateTime
    }
}

// MARK: - 数字格式化扩展（从共享模块导入）

// MARK: - 字符串智能缩写扩展
extension String {
    var smartAbbreviated: String {
        let components = self.split(separator: " ").map(String.init)
        guard components.count > 1 else { return self }
        
        // 如果只有两个词，保持原样
        if components.count == 2 {
            return self
        }
        
        // 多个词的情况：缩写除了最后一个词之外的所有词
        let abbreviatedComponents = components.dropLast().map { word in
            String(word.prefix(1)) + "."
        }
        
        let lastName = components.last ?? ""
        return (abbreviatedComponents + [lastName]).joined(separator: " ")
    }
    
    var adaptiveAbbreviated: String {
        let components = self.split(separator: " ").map(String.init)
        guard components.count > 1 else { return self }
        
        // 如果总长度较短，直接返回
        if self.count <= 12 {
            return self
        }
        
        // 如果只有两个词且较长，缩写第一个词
        if components.count == 2 {
            let firstName = components[0]
            let lastName = components[1]
            return "\(firstName.prefix(1)). \(lastName)"
        }
        
        // 多个词的情况：缩写除了最后一个词之外的所有词
        let abbreviatedComponents = components.dropLast().map { word in
            String(word.prefix(1)) + "."
        }
        
        let lastName = components.last ?? ""
        return (abbreviatedComponents + [lastName]).joined(separator: " ")
    }
}

// 观察切换按钮缩放动画的辅助修饰器
private struct SwitchScaleObserver: AnimatableModifier {
    var scale: CGFloat
    var onUpdate: (Double) -> Void

    var animatableData: CGFloat {
        get { scale }
        set {
            scale = newValue
            onUpdate(Double(newValue))
        }
    }

    func body(content: Content) -> some View {
        content
    }
}
// MARK: - 使用共享的数据模型
// WidgetScholarInfo和CitationTrend现在从共享模块导入
// appGroupIdentifier也从共享常量导入

struct CiteTrackWidgetEntry: TimelineEntry {
    let date: Date
    let scholars: [WidgetScholarInfo]
    let primaryScholar: WidgetScholarInfo?
    let totalCitations: Int
    var lastRefreshTime: Date?
    var widgetTheme: WidgetTheme = .system
}

// MARK: - 读取 Widget 主题（直接从 App Group）
private func readWidgetTheme() -> WidgetTheme {
    if let ag = UserDefaults(suiteName: appGroupIdentifier) {
        let raw = ag.string(forKey: "WidgetTheme")
        print("🧪 [Widget] AppGroup(\(appGroupIdentifier)) 读取 WidgetTheme=\(raw ?? "nil")")
        if let raw, let t = WidgetTheme(rawValue: raw) { return t }
    }
    // 回退：标准存储
    let rawStd = UserDefaults.standard.string(forKey: "WidgetTheme")
    print("🧪 [Widget] Standard 读取 WidgetTheme=\(rawStd ?? "nil")")
    if let rawStd, let t = WidgetTheme(rawValue: rawStd) { return t }
    return .system
}

// MARK: - 数据提供者：专注数据，无杂音
struct CiteTrackWidgetProvider: TimelineProvider {
    
    private let widgetDataService = WidgetDataService.shared
    
    // 辅助方法：从学者列表中获取选中的学者
    private func getSelectedScholar(from scholars: [WidgetScholarInfo], selectedId: String?) -> WidgetScholarInfo? {
        guard let selectedId = selectedId else { return nil }
        return scholars.first { $0.id == selectedId }
    }
    
    func placeholder(in context: Context) -> CiteTrackWidgetEntry {
        print("🚨🚨🚨 WIDGET EXTENSION 启动 - 使用新的数据架构！🚨🚨🚨")
        return CiteTrackWidgetEntry(
            date: Date(),
            scholars: [],
            primaryScholar: nil,
            totalCitations: 0,
            lastRefreshTime: nil
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (CiteTrackWidgetEntry) -> ()) {
        print("🔄 [Widget] getSnapshot 被调用 - 使用新的数据架构")
        
        Task {
            do {
                let widgetData = try await widgetDataService.getWidgetData()
                let scholars = widgetData.scholars
                
                // 获取选中的学者或引用数最多的学者
                let primary = getSelectedScholar(from: scholars, selectedId: widgetData.selectedScholarId) ?? 
                             scholars.max(by: { ($0.citations ?? 0) < ($1.citations ?? 0) })
                
                let theme = readWidgetTheme()
                let entry = CiteTrackWidgetEntry(
                    date: Date(),
                    scholars: Array(scholars.prefix(4)),
                    primaryScholar: primary,
                    totalCitations: widgetData.totalCitations,
                    lastRefreshTime: widgetData.lastUpdateTime,
                    widgetTheme: theme
                )
                
                completion(entry)
            } catch {
                print("❌ [Widget] getSnapshot 加载数据失败: \(error)")
                // 提供空数据作为回退
                completion(CiteTrackWidgetEntry(
                    date: Date(),
                    scholars: [],
                    primaryScholar: nil,
                    totalCitations: 0,
                    lastRefreshTime: nil,
                    widgetTheme: .system
                ))
            }
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<CiteTrackWidgetEntry>) -> ()) {
        print("🔄 [Widget] getTimeline 被调用 - 使用新的数据架构")
        
        Task {
            do {
                let widgetData = try await widgetDataService.getWidgetData()
                let scholars = widgetData.scholars
                
                // 获取选中的学者或引用数最多的学者
                let primary = getSelectedScholar(from: scholars, selectedId: widgetData.selectedScholarId) ?? 
                             scholars.max(by: { ($0.citations ?? 0) < ($1.citations ?? 0) })
                
                // 创建带有刷新时间和主题的条目
                let theme = readWidgetTheme()
                let entryWithRefreshTime = CiteTrackWidgetEntry(
                    date: Date(),
                    scholars: Array(scholars.prefix(4)),
                    primaryScholar: primary,
                    totalCitations: widgetData.totalCitations,
                    lastRefreshTime: widgetData.lastUpdateTime,
                    widgetTheme: theme
                )
                
                // 根据数据更新频率调整刷新策略
                let nextUpdate: Date
                if context.isPreview {
                    // 预览模式下不需要频繁更新
                    nextUpdate = Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date()
                } else {
                    // 正常模式下每15分钟检查一次数据更新
                    nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
                }
                
                let timeline = Timeline(entries: [entryWithRefreshTime], policy: .after(nextUpdate))
                completion(timeline)
                
            } catch {
                print("❌ [Widget] getTimeline 加载数据失败: \(error)")
                
                // 提供空数据作为回退
                let fallbackEntry = CiteTrackWidgetEntry(
                    date: Date(),
                    scholars: [],
                    primaryScholar: nil,
                    totalCitations: 0,
                    lastRefreshTime: nil,
                    widgetTheme: .system
                )
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
                let timeline = Timeline(entries: [fallbackEntry], policy: .after(nextUpdate))
                completion(timeline)
            }
        }
    }

    /// 若检测到"全局完成时间"晚于该学者的开始时间，则写入该学者 LastRefreshTime_<id> 并清除进行中标记
    private func reconcilePerScholarRefreshCompletion(for scholarId: String) {
        let groupID = appGroupIdentifier
        let startKey = "RefreshStartTime_\(scholarId)"
        let lastKey = "LastRefreshTime_\(scholarId)"
        let inKey = "RefreshInProgress_\(scholarId)"

        // 读取学者开始时间
        var startTime: Date?
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            startTime = appGroupDefaults.object(forKey: startKey) as? Date
        }
        if startTime == nil {
            startTime = UserDefaults.standard.object(forKey: startKey) as? Date
        }

        guard let s = startTime else { return }

        // 读取全局 LastRefreshTime 作为回落
        let globalLast = getLastRefreshTime()
        guard let g = globalLast, g > s else { return }

        // 写入该学者的 LastRefreshTime_<id> 并清除进行中
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            appGroupDefaults.set(g, forKey: lastKey)
            appGroupDefaults.set(false, forKey: inKey)
            appGroupDefaults.synchronize()
        }
        UserDefaults.standard.set(g, forKey: lastKey)
        UserDefaults.standard.set(false, forKey: inKey)
    }
    
    /// 获取用户选择的学者
    private func getSelectedScholar(from scholars: [WidgetScholarInfo]) -> WidgetScholarInfo? {
        let groupID = appGroupIdentifier
        
        // 首先尝试从App Group读取选择的学者ID
        var selectedId: String?
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            selectedId = appGroupDefaults.string(forKey: "SelectedWidgetScholarId")
        }
        
        // 回退到标准UserDefaults
        if selectedId == nil {
            selectedId = UserDefaults.standard.string(forKey: "SelectedWidgetScholarId")
        }
        
        guard let scholarId = selectedId else { return nil }
        
        let selected = scholars.first { $0.id == scholarId }
        if let selected = selected {
            print("✅ [Widget] 使用用户选择的学者: \(selected.displayName)")
        }
        
        return selected
    }
    
    /// 🎯 简化数据加载：优先从App Group读取，回退到标准位置
    private func loadScholars() -> [WidgetScholarInfo] {
        print("🔍 [Widget] 开始加载学者数据...")
        
        let groupID = appGroupIdentifier
        print("🔍 [Widget] 使用App Group ID: \(groupID)")
        
        // 首先尝试从App Group读取
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            print("🔍 [Widget] App Group UserDefaults创建成功")
            
            // 列出App Group中的所有键
            let allKeys = appGroupDefaults.dictionaryRepresentation().keys
            print("🔍 [Widget] App Group中的所有键: \(Array(allKeys))")
            
            if let data = appGroupDefaults.data(forKey: "WidgetScholars") {
                print("🔍 [Widget] 从App Group找到数据，大小: \(data.count) bytes")
                if let scholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
                    print("✅ [Widget] 从App Group加载了 \(scholars.count) 位学者")
                    return scholars
                } else {
                    print("❌ [Widget] App Group数据解码失败")
                }
            } else {
                print("⚠️ [Widget] App Group中没有WidgetScholars数据")
            }
        } else {
            print("❌ [Widget] 无法创建App Group UserDefaults")
        }
        
        // 回退到标准UserDefaults
        print("🔍 [Widget] 尝试标准UserDefaults...")
        let standardKeys = UserDefaults.standard.dictionaryRepresentation().keys
        print("🔍 [Widget] 标准UserDefaults中的所有键: \(Array(standardKeys))")
        
        if let data = UserDefaults.standard.data(forKey: "WidgetScholars") {
            print("🔍 [Widget] 从标准存储找到数据，大小: \(data.count) bytes")
            if let scholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
                print("✅ [Widget] 从标准存储加载了 \(scholars.count) 位学者")
                return scholars
            } else {
                print("❌ [Widget] 标准存储数据解码失败")
            }
        } else {
            print("⚠️ [Widget] 标准存储中也没有WidgetScholars数据")
        }
        
        print("📱 [Widget] 暂无学者数据（已检查App Group和标准存储）")
        return []
    }
    
    /// 获取最后刷新时间
    private func getLastRefreshTime() -> Date? {
        let groupID = appGroupIdentifier
        
        // 首先尝试从App Group读取
        if let appGroupDefaults = UserDefaults(suiteName: groupID),
           let lastRefresh = appGroupDefaults.object(forKey: "LastRefreshTime") as? Date {
            return lastRefresh
        }
        
        // 回退到标准UserDefaults
        return UserDefaults.standard.object(forKey: "LastRefreshTime") as? Date
    }
    
    /// 保存当前引用数作为月度历史数据
    private func saveCurrentCitationsAsHistory(scholars: [WidgetScholarInfo]) {
        let groupID = appGroupIdentifier
        
        for scholar in scholars {
            if let citations = scholar.citations {
                // 保存到 App Group
                if let appGroupDefaults = UserDefaults(suiteName: groupID) {
                    appGroupDefaults.set(citations, forKey: "MonthlyPreviousCitations_\(scholar.id)")
                }
                // 同时保存到标准存储
                UserDefaults.standard.set(citations, forKey: "MonthlyPreviousCitations_\(scholar.id)")
            }
        }
    }
}

// MARK: - App Intents：让小组件具备交互能力

/// 🎯 学者选择Intent - 核心交互功能
@available(iOS 17.0, *)
struct SelectScholarIntent: AppIntent {
    static var title: LocalizedStringResource = "Select Scholar"
    static var description: IntentDescription = "select_scholar_description"
    static var openAppWhenRun: Bool = false  // 不需要打开App
    
    @Parameter(title: "scholar_parameter", description: "scholar_parameter_description")
    var selectedScholar: ScholarEntity?
    
    func perform() async throws -> some IntentResult {
        print("🎯 [Intent] 学者选择Intent被触发")
        
        guard let scholar = selectedScholar else {
            // 如果没有提供学者，只是触发刷新
            print("⚠️ [Intent] 未提供学者参数，仅触发刷新")
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        
        print("✅ [Intent] 用户选择了学者: \(scholar.displayName)")
        
        let groupID = appGroupIdentifier
        
        // 保存到App Group UserDefaults
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            appGroupDefaults.set(scholar.id, forKey: "SelectedWidgetScholarId")
            appGroupDefaults.set(scholar.displayName, forKey: "SelectedWidgetScholarName")
            print("✅ [Intent] 已保存到App Group: \(scholar.displayName)")
        }
        
        // 同时保存到标准UserDefaults作为备份
        UserDefaults.standard.set(scholar.id, forKey: "SelectedWidgetScholarId")
        UserDefaults.standard.set(scholar.displayName, forKey: "SelectedWidgetScholarName")
        
        // 触发小组件刷新
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
    
    static var parameterSummary: some ParameterSummary {
        Summary("select_scholar \(\.$selectedScholar)")
    }
}

/// 🎯 学者实体 - 用于Intent参数
@available(iOS 17.0, *)
struct ScholarEntity: AppEntity {
    let id: String
    let displayName: String
    let citations: Int?
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: citations.map { "\($0) citations" } ?? "No Data Available"
        )
    }
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "scholar"
    
    static var defaultQuery = ScholarEntityQuery()
}

/// 🎯 学者查询 - 提供可选择的学者列表
@available(iOS 17.0, *)
struct ScholarEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ScholarEntity] {
        let scholars = loadAllScholars()
        return scholars.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [ScholarEntity] {
        return loadAllScholars()
    }
    
    private func loadAllScholars() -> [ScholarEntity] {
        // 使用全局定义的 appGroupIdentifier
        
        // 首先尝试从App Group读取
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let data = appGroupDefaults.data(forKey: "WidgetScholars"),
           let widgetScholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
            let scholars = widgetScholars.map { scholar in
                ScholarEntity(
                    id: scholar.id,
                    displayName: scholar.displayName,
                    citations: scholar.citations
                )
            }
            print("✅ [Intent] 从App Group加载了 \(scholars.count) 位学者供选择")
            return scholars
        }
        
        // 回退到标准UserDefaults
        if let data = UserDefaults.standard.data(forKey: "WidgetScholars"),
           let widgetScholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
            let scholars = widgetScholars.map { scholar in
                ScholarEntity(
                    id: scholar.id,
                    displayName: scholar.displayName,
                    citations: scholar.citations
                )
            }
            print("✅ [Intent] 从标准存储加载了 \(scholars.count) 位学者供选择")
            return scholars
        }
        
        print("📱 [Intent] 无法加载学者数据（已检查App Group和标准存储）")
        return []
    }
}



/// 🔄 强制刷新Intent - 用于调试
@available(iOS 17.0, *)
struct ForceRefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Force Refresh Widget"
    static var description: IntentDescription = "force_refresh_description"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        print("🔄 [ForceRefreshIntent] 用户点击了强制刷新按钮")
        print("🔄 [ForceRefreshIntent] 开始强制刷新流程...")
        
        // 设置一个标记，让数据提供者知道这是强制刷新
        UserDefaults.standard.set(Date(), forKey: "ForceRefreshTriggered")
        UserDefaults.standard.synchronize()
        print("🔄 [ForceRefreshIntent] 已设置强制刷新标记")
        
        // 强制触发小组件刷新
        WidgetCenter.shared.reloadAllTimelines()
        print("🔄 [ForceRefreshIntent] WidgetCenter.reloadAllTimelines() 已调用")
        
        // 等待一小段时间让系统处理
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        // 再次强制刷新
        WidgetCenter.shared.reloadAllTimelines()
        print("🔄 [ForceRefreshIntent] 第二次刷新已触发")
        
        return .result()
    }
}

/// 🧪 调试测试Intent - 验证AppIntents系统
@available(iOS 17.0, *)
struct DebugTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Debug Test"
    static var description: IntentDescription = "debug_test_description"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        print("🧪 [DebugTestIntent] 调试测试Intent被触发！")
        return .result()
    }
}

/// 🔄 快速刷新Intent - 修复动画触发
@available(iOS 17.0, *)
struct QuickRefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Data"
    static var description: IntentDescription = "refresh_data_description"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        // Relay widget event to main app via AppGroup UserDefaults
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            var pending = defaults.array(forKey: "PendingAnalyticsEvents") as? [[String: Any]] ?? []
            pending.append(["event": "widget_refresh_triggered", "timestamp": Date().timeIntervalSince1970])
            defaults.set(pending, forKey: "PendingAnalyticsEvents")
        }
        let intentStartTime = Date()
        let startTimestamp = intentStartTime.timeIntervalSince1970
        NSLog("🚨🚨🚨 QuickRefreshIntent 被触发！！！ 时间戳: \(startTimestamp)")
        print("🚨🚨🚨 [Intent] QuickRefreshIntent 被触发！！！ 时间戳: \(startTimestamp)")
        print("🔄 [Intent] ===== 新版本代码 - 用户触发小组件刷新 =====")
        print("⏱️ [Intent] 🎯 计时开始: \(intentStartTime)")

        let groupIdentifier = appGroupIdentifier
        let timestamp = Date()
        
        // 🎯 修复：立即设置刷新状态标记，确保按钮点击后立即模糊
        var selectedScholarId: String?
        
        // 首先获取当前选中的学者ID
        if let appGroupDefaults = UserDefaults(suiteName: groupIdentifier) {
            selectedScholarId = appGroupDefaults.string(forKey: "SelectedWidgetScholarId")
        }
        if selectedScholarId == nil {
            selectedScholarId = UserDefaults.standard.string(forKey: "SelectedWidgetScholarId")
        }
        
        let effectiveScholarId = selectedScholarId ?? ""
        print("🔄 [Intent] 有效学者ID: \(effectiveScholarId)")
        
        // 🎯 关键修复：立即设置所有必要的刷新标记
        func setRefreshMarkers(to defaults: UserDefaults, scholarId: String?) {
            // 通用键
            defaults.set(timestamp, forKey: "RefreshStartTime")
            defaults.set(true, forKey: "RefreshTriggered")
            defaults.set(timestamp, forKey: "RefreshTriggerTime")
            
            // 学者专属键
            if let sid = scholarId, !sid.isEmpty {
                defaults.set(timestamp, forKey: "RefreshStartTime_\(sid)")
                defaults.set(timestamp, forKey: "RefreshTriggerTime_\(sid)")
                print("🔄 [Intent] 设置学者专属刷新标记: \(sid)")
            }
            defaults.synchronize()
        }
        
        let markersSetTime = Date()
        let markersElapsed = markersSetTime.timeIntervalSince(intentStartTime) * 1000
        print("⏱️ [Intent] 获取学者ID用时: \(String(format: "%.1f", markersElapsed))ms")
        
        // App Group UserDefaults
        if let appGroupDefaults = UserDefaults(suiteName: groupIdentifier) {
            setRefreshMarkers(to: appGroupDefaults, scholarId: effectiveScholarId)
            let agSetTime = Date()
            let agElapsed = agSetTime.timeIntervalSince(markersSetTime) * 1000
            print("⏱️ [Intent] App Group 标记设置用时: \(String(format: "%.1f", agElapsed))ms")
        }
        
        // Standard UserDefaults (兜底)
        setRefreshMarkers(to: UserDefaults.standard, scholarId: effectiveScholarId)
        let stdSetTime = Date()
        let stdElapsed = stdSetTime.timeIntervalSince(markersSetTime) * 1000
        print("⏱️ [Intent] Standard 标记设置用时: \(String(format: "%.1f", stdElapsed))ms")
        

        
        let beforeReloadTime = Date()
        WidgetCenter.shared.reloadAllTimelines()
        let afterReloadTime = Date()
        let reloadElapsed = afterReloadTime.timeIntervalSince(beforeReloadTime) * 1000
        let totalElapsedSoFar = afterReloadTime.timeIntervalSince(intentStartTime) * 1000
        print("⏱️ [Intent] 立即设置模糊状态并刷新Widget")
        print("⏱️ [Intent] reloadAllTimelines 调用用时: \(String(format: "%.1f", reloadElapsed))ms")
        print("⏱️ [Intent] 🎯 从点击到模糊设置完成总用时: \(String(format: "%.1f", totalElapsedSoFar))ms")
        
        // 🎯 存储开始时间戳，供Widget检测使用
        if let appGroupDefaults = UserDefaults(suiteName: groupIdentifier) {
            appGroupDefaults.set(intentStartTime, forKey: "IntentStartTime")
            appGroupDefaults.synchronize()
        }
        UserDefaults.standard.set(intentStartTime, forKey: "IntentStartTime")
        UserDefaults.standard.synchronize()
        
        print("✅ [Intent] 🔄 刷新标记已设置: RefreshTriggered = true")
        
        // 🎯 修复：立即开始网络请求，不等待，确保最快响应
        print("🔄 [Intent] 立即开始后台数据获取")
        
        // 在 Intent 内直接后台拉取并写回数据（使用 async/await，确保返回前完成并清理标记）
        if let sid = selectedScholarId, !sid.isEmpty {
            print("📡 [Intent] 开始后台拉取学者数据: sid=\(sid)")
            func fetchScholarInfoInlineAsync(for scholarId: String) async throws -> (name: String, citations: Int) {
                guard let url = URL(string: "https://scholar.google.com/citations?user=\(scholarId)&hl=en") else {
                    throw NSError(domain: "InvalidURL", code: -1)
                }
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                }
                let html = String(data: data, encoding: .utf8) ?? ""
                // Reject a CAPTCHA / consent / "unusual traffic" interstitial (HTTP 200
                // but not a real profile). The cookieless widget request hits these often;
                // parsing one as success used to write a garbage/0 citation back to the app.
                let lowerHtml = html.lowercased()
                let blocked = html.isEmpty
                    || ["gs_captcha", "g-recaptcha", "recaptcha", "/sorry/", "unusual traffic", "captcha-form"].contains(where: { lowerHtml.contains($0) })
                    || (!lowerHtml.contains("gsc_prf_in") && !lowerHtml.contains("gsc_rsb_std"))
                if blocked { throw NSError(domain: "Blocked", code: -429, userInfo: [NSLocalizedDescriptionKey: "rate limited / captcha"]) }
                func firstMatch(_ pattern: String, _ text: String) -> String? {
                    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
                    let range = NSRange(text.startIndex..., in: text)
                    guard let m = regex.firstMatch(in: text, options: [], range: range), m.numberOfRanges > 1 else { return nil }
                    let r = m.range(at: 1)
                    guard let rr = Range(r, in: text) else { return nil }
                    return String(text[rr])
                }
                let namePatterns = [
                    #"<div id=\"gsc_prf_in\">([^<]+)</div>"#,
                    #"<div[^>]*class=\"gsc_prf_in\"[^>]*>([^<]+)</div>"#
                ]
                var name = ""
                for p in namePatterns { if let v = firstMatch(p, html) { name = v.trimmingCharacters(in: .whitespacesAndNewlines); break } }
                // Only the real stats cell — the old greedy fallbacks grabbed an arbitrary
                // number anywhere on the page. Missing cell => throw (do NOT write a 0).
                let citationPatterns = [
                    #"<td[^>]*class=\"gsc_rsb_std\"[^>]*>(\d+)</td>"#,
                    #"Citations</a></td><td[^>]*class=\"gsc_rsb_std\"[^>]*>(\d+)</td>"#
                ]
                var parsed: Int? = nil
                for p in citationPatterns { if let v = firstMatch(p, html), let c = Int(v) { parsed = c; break } }
                guard let citations = parsed else {
                    throw NSError(domain: "ParseError", code: -1, userInfo: [NSLocalizedDescriptionKey: "citations cell not found"])
                }
                if name.isEmpty { name = scholarId }

                // Widget Extension 无法访问 Shared 模块，所以不在这里解析论文列表
                // 论文列表的解析和缓存由主 App 的 GoogleScholarService 处理

                return (name: name, citations: citations)
            }
            do {
                let info = try await fetchScholarInfoInlineAsync(for: sid)
                let now = Date()
                var scholars: [WidgetScholarInfo] = []
                if let appGroup = UserDefaults(suiteName: groupIdentifier),
                   let data = appGroup.data(forKey: "WidgetScholars"),
                   let loaded = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
                    scholars = loaded
                } else if let data = UserDefaults.standard.data(forKey: "WidgetScholars"),
                          let loaded = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
                    scholars = loaded
                }
                if let idx = scholars.firstIndex(where: { $0.id == sid }) {
                    let old = scholars[idx]
                    let updated = WidgetScholarInfo(
                        id: old.id,
                        displayName: info.name.isEmpty ? old.displayName : info.name,
                        institution: old.institution,
                        citations: info.citations,
                        hIndex: old.hIndex,
                        lastUpdated: now,
                        // 统一以后端预计算结果为准，保留旧的增长值，避免Widget侧自算
                        weeklyGrowth: old.weeklyGrowth,
                        monthlyGrowth: old.monthlyGrowth,
                        quarterlyGrowth: old.quarterlyGrowth
                    )
                    scholars[idx] = updated
                }
                if let encoded = try? JSONEncoder().encode(scholars) {
                    if let appGroup = UserDefaults(suiteName: groupIdentifier) {
                        appGroup.set(encoded, forKey: "WidgetScholars")
                        appGroup.set(now, forKey: "LastRefreshTime_\(sid)")
                        appGroup.set(now, forKey: "LastRefreshTime") // 写全局更新时间
                        appGroup.synchronize()
                        print("🧪 [Widget] AppGroup 写入 LastRefreshTime & LastRefreshTime_\(sid): \(now)")
                    }
                    UserDefaults.standard.set(encoded, forKey: "WidgetScholars")
                    UserDefaults.standard.set(now, forKey: "LastRefreshTime_\(sid)")
                    UserDefaults.standard.set(now, forKey: "LastRefreshTime") // 写全局更新时间
                    UserDefaults.standard.synchronize()
                    print("🧪 [Widget] Standard 写入 LastRefreshTime & LastRefreshTime_\(sid): \(now)")
                    // 通知主App刷新读取
                    postDarwinNotification("com.citetrack.lastRefreshTimeUpdated")
                }
                
                // 历史记录统一由后端数据层维护，Widget侧不再落库，避免与图表数据不一致
                
                // 🎯 新方案：数据返回后立即清除模糊状态
                print("🔄 [Intent] 数据更新完成，立即清除模糊状态")
                
                // 立即清除所有模糊相关标记
                func clearAllBlurMarkers(from defaults: UserDefaults, scholarId: String) {
                    // 清除旧的标记
                    defaults.removeObject(forKey: "RefreshInProgress_\(scholarId)")
                    defaults.removeObject(forKey: "RefreshStartTime_\(scholarId)")
                    defaults.removeObject(forKey: "RefreshTriggerTime_\(scholarId)")
                    defaults.synchronize()
                    print("🔄 [Intent] ✅ 已清除刷新标记")
                }
                
                if let ag = UserDefaults(suiteName: groupIdentifier) {
                    clearAllBlurMarkers(from: ag, scholarId: sid)
                }
                clearAllBlurMarkers(from: UserDefaults.standard, scholarId: sid)
                
                // 🎯 立即设置对勾状态，无需等待Widget检查
                let ackKey = "ShowRefreshAck_\(sid)"
                if let ag = UserDefaults(suiteName: groupIdentifier) {
                    ag.set(true, forKey: ackKey)
                    ag.synchronize()
                    print("⚡ [Intent] 立即设置对勾状态: \(ackKey) = true (App Group)")
                }
                UserDefaults.standard.set(true, forKey: ackKey)
                print("⚡ [Intent] 立即设置对勾状态: \(ackKey) = true (Standard)")
                
                // 立即刷新widget以显示对勾
                WidgetCenter.shared.reloadAllTimelines()
                print("✅ [Intent] 后台刷新完成并写回: sid=\(sid), citations=\(info.citations)")
                print("✅ [Intent] 已保存引用历史记录: \(info.citations) at \(now)")
                print("✅ [Intent] 对勾状态已立即设置完成")
            } catch {
                print("❌ [Intent] 后台拉取失败: sid=\(sid), error=\(error.localizedDescription)")

                // Do NOT bump LastRefreshTime on failure. Advertising a fresh timestamp for
                // a refresh that got blocked/mis-parsed made the app's widget-merge treat the
                // stale/wrong widget value as "newer" and revert the user's correct count.
                // We only clear the in-progress/blur markers below so the widget doesn't hang.

                // 🎯 修复：失败时也立即清除模糊状态
                print("🔄 [Intent] 失败情况，立即清除模糊状态")
                
                func clearAllBlurMarkersOnFailure(from defaults: UserDefaults, scholarId: String) {
                    // 清除旧的标记
                    defaults.removeObject(forKey: "RefreshInProgress_\(scholarId)")
                    defaults.removeObject(forKey: "RefreshStartTime_\(scholarId)")
                    defaults.removeObject(forKey: "RefreshTriggerTime_\(scholarId)")
                    defaults.synchronize()
                    print("🔄 [Intent] ✅ 失败时已清除刷新标记")
                }
                
                if let ag = UserDefaults(suiteName: groupIdentifier) {
                    clearAllBlurMarkersOnFailure(from: ag, scholarId: sid)
                }
                clearAllBlurMarkersOnFailure(from: UserDefaults.standard, scholarId: sid)
                
                // 立即刷新widget以清除模糊效果
                WidgetCenter.shared.reloadAllTimelines()
                print("🔄 [Intent] 失败情况下模糊状态立即清除完成")
            }
        } else {
            print("⚠️ [Intent] 未找到 SelectedWidgetScholarId，跳过后台拉取")
        }
        
        // 立即触发小组件刷新（展示 InProg 态）
        print("🔄 [Intent] 触发小组件刷新...")
        WidgetCenter.shared.reloadAllTimelines()
        print("🔄 [Intent] 小组件刷新触发完成")
        
        print("🚨🚨🚨 [Intent] QuickRefreshIntent 执行完成！！！")
        return .result()
    }
}

/// 🎯 简化的学者切换Intent - 修复动画触发
@available(iOS 17.0, *)
struct ToggleScholarIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Scholar"
    static var description: IntentDescription = "switch_scholar_description"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        // Relay widget event to main app via AppGroup UserDefaults
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            var pending = defaults.array(forKey: "PendingAnalyticsEvents") as? [[String: Any]] ?? []
            pending.append(["event": "widget_scholar_switched", "timestamp": Date().timeIntervalSince1970])
            defaults.set(pending, forKey: "PendingAnalyticsEvents")
        }
        print("🎯 [Intent] ===== 新版本代码 - 用户触发学者切换 =====")

        let groupIdentifier = appGroupIdentifier
        
        // 获取所有学者
        var scholars: [WidgetScholarInfo] = []
        if let appGroupDefaults = UserDefaults(suiteName: groupIdentifier),
           let data = appGroupDefaults.data(forKey: "WidgetScholars"),
           let loadedScholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
            scholars = loadedScholars
        } else if let data = UserDefaults.standard.data(forKey: "WidgetScholars"),
                  let loadedScholars = try? JSONDecoder().decode([WidgetScholarInfo].self, from: data) {
            scholars = loadedScholars
        }
        
        guard !scholars.isEmpty else {
            print("⚠️ [Intent] 没有可用的学者")
            return .result()
        }
        
        // 获取当前选择的学者
        var currentSelectedId: String?
        if let appGroupDefaults = UserDefaults(suiteName: groupIdentifier) {
            currentSelectedId = appGroupDefaults.string(forKey: "SelectedWidgetScholarId")
        }
        if currentSelectedId == nil {
            currentSelectedId = UserDefaults.standard.string(forKey: "SelectedWidgetScholarId")
        }
        
        // 找到下一个学者
        var nextScholar: WidgetScholarInfo
        if let currentId = currentSelectedId,
           let currentIndex = scholars.firstIndex(where: { $0.id == currentId }) {
            let nextIndex = (currentIndex + 1) % scholars.count
            nextScholar = scholars[nextIndex]
        } else if let first = scholars.first {
            nextScholar = first
        } else {
            return .result()
        }
        
        // 设置切换标记，不清除其他标记
        if let appGroupDefaults = UserDefaults(suiteName: groupIdentifier) {
            appGroupDefaults.set(nextScholar.id, forKey: "SelectedWidgetScholarId")
            appGroupDefaults.set(nextScholar.displayName, forKey: "SelectedWidgetScholarName")
            appGroupDefaults.set(true, forKey: "ScholarSwitched")
            appGroupDefaults.synchronize()
        }
        UserDefaults.standard.set(nextScholar.id, forKey: "SelectedWidgetScholarId")
        UserDefaults.standard.set(nextScholar.displayName, forKey: "SelectedWidgetScholarName")
        UserDefaults.standard.set(true, forKey: "ScholarSwitched")
        UserDefaults.standard.synchronize()
        
        print("✅ [Intent] 🎯 切换标记已设置: ScholarSwitched = true")
        
        // 立即触发小组件刷新
        WidgetCenter.shared.reloadAllTimelines()
        
        print("✅ [Intent] 已切换到学者: \(nextScholar.displayName)")
        return .result()
    }
}

// MARK: - 小组件视图：一个组件，三种尺寸，完美适配

struct CiteTrackWidgetView: View {
    let entry: CiteTrackWidgetEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        func widgetBackgroundColor(for theme: WidgetTheme) -> Color {
            switch theme {
            case .light:
                return Color.white
            case .dark:
                return Color.black
            case .system:
                return Color.clear // 交给系统材质
            }
        }
        // 智能主题应用：考虑系统当前颜色方案
        let appliedScheme: ColorScheme = {
            switch entry.widgetTheme {
            case .light:
                // 浅色主题：始终使用浅色
                return .light
            case .dark:
                // 深色主题：始终使用深色
                return .dark
            case .system:
                // 跟随系统：在 Widget 中默认使用浅色，但让系统决定最终渲染
                return .light
            }
        }()
        
        // 构造内容并按需注入颜色方案（使用类型擦除便于返回一致类型）
        let baseContent: AnyView = {
            switch family {
            case .systemSmall:
                return AnyView(SmallWidgetView(entry: entry))
            case .systemMedium:
                return AnyView(MediumWidgetView(entry: entry))
            case .systemLarge:
                return AnyView(LargeWidgetView(entry: entry))
            default:
                return AnyView(SmallWidgetView(entry: entry))
            }
        }()
        
        // 应用主题：仅在浅/深色时强制注入；跟随系统时完全交给系统，避免字体配色错乱
        if entry.widgetTheme == .system {
            print("🎨 [Widget] 应用主题: system -> defer to system color scheme")
            return AnyView(baseContent)
        } else {
            print("🎨 [Widget] 应用主题: \(entry.widgetTheme.rawValue) -> \(appliedScheme)")
            let themedContent = baseContent
                .environment(\.colorScheme, appliedScheme)
                .preferredColorScheme(appliedScheme)
            return AnyView(themedContent)
        }
    }
}

/// 🎯 小尺寸：单一学者，极简聚焦 - 乔布斯式设计
struct SmallWidgetView: View {
    let entry: CiteTrackWidgetEntry
    @State private var refreshAngle: Double = 0
    // 使用 isSwitching 驱动缩放，避免在 WidgetKit 重建视图时丢失回弹
    @State private var animationTrigger: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var isSwitching: Bool = false
    // 🎯 从UserDefaults读取对号状态，避免Xcode调试时被重置
    @State private var showRefreshAck: Bool = false
    
    // 🎯 当前显示的学者ID，用于对号状态绑定
    private var currentScholarId: String? {
        return entry.primaryScholar?.id
    }
    
    // 🎯 检查当前学者是否应该显示对号状态
    private var shouldShowRefreshAck: Bool {
        guard let scholarId = currentScholarId else { return false }
        
        // 从持久化存储中读取对号状态
        let key = "ShowRefreshAck_\(scholarId)"
        
        if let appGroup = UserDefaults(suiteName: appGroupIdentifier) {
            return appGroup.bool(forKey: key)
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    @State private var refreshBlinkOn: Bool = false
    // 刷新时主体内容转场：淡出+轻微缩放，再淡入
    @State private var contentScale: Double = 1.0
    @State private var contentOpacity: Double = 1.0
    // 切换按钮仅高亮，不替换为勾号
    @State private var observedSwitchScale: Double = 1.0
    // 切换按钮脉冲反馈所需状态（不改变按钮本体大小）
    @State private var showSwitchPulse: Bool = false
    @State private var switchPulseScale: Double = 1.0
    @State private var switchPulseOpacity: Double = 0.0
    // 切换按钮背景高亮独立状态，避免长时间停留
    @State private var switchHighlight: Bool = false
    
    var body: some View {
        let widgetRenderTime = Date()
        let _ = print("📱 [Widget] SmallWidgetView body 被调用 - 时间: \(widgetRenderTime)")
        
        if let scholar = entry.primaryScholar {
            ZStack {
                VStack(spacing: 0) {
                    // 顶部：学者信息和状态（固定高度）
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(scholar.displayName.adaptiveAbbreviated)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            
                            Spacer()
                            
                            // 状态指示器：默认灰色，今天有刷新则绿色
                            Circle()
                                .fill(isScholarUpdatedToday(scholar.id) ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                        }
                        
                        // 机构信息占位，确保固定高度
                        HStack {
                            if let institution = scholar.institution {
                                Text(institution)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            } else {
                                Text(" ")
                                    .font(.caption2)
                                    .foregroundColor(.clear)
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 44) // 固定顶部区域高度
                    .padding(.top, 12) // 减少顶部padding让整体上移
                    .padding(.horizontal, 12)
                    
                    Spacer()
                    
                    // 中心：大引用数显示（刷新转场：淡出淡入 + 轻缩放）
                    ZStack {
                    VStack(spacing: 6) {
                        Text((scholar.citations ?? 0).formattedNumber)
                            .font(.system(size: 42, weight: .heavy)) // 再次放大字体
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.5) // 允许更大缩放范围
                            .lineLimit(1)

                        
                        Text("citations_label".widgetLocalized)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        }
                        .padding(.horizontal, 6)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .scaleEffect(contentScale)
                        .opacity(contentOpacity)

                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: contentScale)
                        .animation(.easeInOut(duration: 0.18), value: contentOpacity)

                    }
                    
                    Spacer()
                    
                    // 为按钮留出空间
                    Color.clear
                        .frame(height: 35) // 进一步减少底部空间，让引用数字位置提高
                    

                }
                
                // 底部：引用数趋势和按钮
                VStack {
                    Spacer()
                    
                    // 引用数趋势显示在按钮区域
                    HStack {
                        // 左下角：切换按钮 - 使用AppIntent
                        if #available(iOS 17.0, *) {
                            Button(intent: ToggleScholarIntent()) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(switchHighlight ? Color.blue.opacity(0.35) : Color.blue.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                }
                                .modifier(SwitchScaleObserver(scale: isSwitching ? 0.88 : 1.0) { current in
                                    if abs(current - observedSwitchScale) > 0.0001 {
                                        observedSwitchScale = current
                                        print("🎯 [Widget] 切换按钮实时缩放: \(String(format: "%.3f", current))  isSwitching=\(isSwitching)")
                                    }
                                })
                            }
                            .buttonStyle(EnhancedWidgetButtonStyle())
                        } else {
                            // iOS 17以下使用Link作为后备
                        Link(destination: URL(string: "citetrack://switch")!) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(16)
                            }
                        }
                        
                        Spacer()
                        
                        // 中间：趋势指示器（固定宽度，包含箭头）
                        HStack {
                            Spacer()
                            HStack(spacing: 3) {
                                Text(scholar.citationTrend.symbol)
                                    .font(.caption2) // 缩小箭头字体
                                Text(scholar.citationTrend.text)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(scholar.citationTrend.color)
                            .lineLimit(1)
                            Spacer()
                        }

                        .frame(minWidth: 80) // 增加中间区域宽度以避免省略号
                        
                        Spacer()
                        
                        // 右下角：刷新按钮 - 使用AppIntent
                        if #available(iOS 17.0, *) {
                            Button(intent: QuickRefreshIntent()) {
                                ZStack {
                                    // 背景根据刷新状态高亮
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.green)
                                        .opacity(0.15)
                                        .frame(width: 32, height: 32)

                                    // 刷新中：转圈图标；完成：对勾
                                    Group {
                                        // 仅在不处于模糊/进行中时才显示对勾
                                        if showRefreshAck {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.title3)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(EnhancedWidgetButtonStyle())
                        } else {
                            // iOS 17以下使用Link作为后备
                        Link(destination: URL(string: "citetrack://refresh")!) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                                .foregroundColor(.green)
                                .frame(width: 32, height: 32)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal, 2) // 更少的padding让按钮更靠近角落
                    .padding(.bottom, 2) // 恢复按钮原来的位置
                }


            }
            .containerBackground(widgetBackgroundColor(for: entry.widgetTheme), for: .widget)
            // .overlay(调试信息已移除)
            .onAppear {
                #if DEBUG
                print("📱 [Widget] ===== SmallWidgetView onAppear =====")
                print("📱 [Widget] 当前 refreshAngle: \(refreshAngle)")
                print("📱 [Widget] 当前 isRefreshing: \(isRefreshing)")
                #endif
                // 🎯 从持久化存储中加载对号状态（每个学者独立）
                loadRefreshAckState()
                // 确保切换按钮初始为原始大小
                // 复位脉冲与高亮状态
                showSwitchPulse = false
                switchPulseScale = 1.0
                switchPulseOpacity = 0.0
                switchHighlight = false
                // 检查动画触发标记（按学者）
                checkRefreshAnimationOnly(for: entry.primaryScholar?.id)
                checkSwitchAnimationOnly()
            }
            .onChange(of: entry.date) {
                print("📱 [Widget] ===== Entry date changed =====")
                print("📱 [Widget] 当前 refreshAngle: \(refreshAngle)")
                print("📱 [Widget] 当前 isRefreshing: \(isRefreshing)")
                // 条目更新时再次检查动画（按学者）
                checkRefreshAnimationOnly(for: entry.primaryScholar?.id)
                checkSwitchAnimationOnly()
                
                // 🎯 Intent已立即设置对勾状态，无需检查
            }
            .onChange(of: entry.primaryScholar?.id) { oldId, newId in
                print("📱 [Widget] ===== 学者切换: \(oldId ?? "nil") -> \(newId ?? "nil") =====")
                // 🎯 学者切换时清除对号状态
                if oldId != newId {
                    showRefreshAck = false
                    print("🔄 [Widget] 学者切换，清除对号状态并持久化为刷新按钮")
                    // 持久化：新学者默认显示刷新按钮
                    if let targetId = newId {
                        saveRefreshAckState(false, for: targetId)
                        // 清理新学者的进行中标记与时间键，避免残留导致误判
                        if let app = UserDefaults(suiteName: appGroupIdentifier) {
                            app.set(false, forKey: "RefreshInProgress_\(targetId)")
                            app.removeObject(forKey: "RefreshStartTime_\(targetId)")
                            app.removeObject(forKey: "RefreshTriggerTime_\(targetId)")
                            app.synchronize()
                            print("🧹 [Widget] 已清理新学者的刷新标记与时间键: \(targetId)")
                        } else {
                            UserDefaults.standard.set(false, forKey: "RefreshInProgress_\(targetId)")
                            UserDefaults.standard.removeObject(forKey: "RefreshStartTime_\(targetId)")
                            UserDefaults.standard.removeObject(forKey: "RefreshTriggerTime_\(targetId)")
                            print("🧹 [Widget] 已清理(Std)新学者的刷新标记与时间键: \(targetId)")
                        }
                    }
                }
            }
            
        } else {
            // 空状态：优雅的引导设计
            VStack(spacing: 16) {
                Spacer()
                
                VStack(spacing: 15) {
                    // 主图标：学术帽
                    Image(systemName: "graduationcap.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue.opacity(0.7))
                    
                    // 主标题
                    Text("start_tracking".widgetLocalized)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // 副标题：引导用户
                    Text("add_scholar_to_track".widgetLocalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                
                // Spacer()
                
                // 底部提示：轻触打开App
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.6))
                    
                    Text("tap_to_open_app".widgetLocalized)
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.6))
                }
                .padding(.bottom, 8)
            }
            .padding()
            .containerBackground(widgetBackgroundColor(for: entry.widgetTheme), for: .widget)
            .widgetURL(URL(string: "citetrack://add-scholar"))
        }
    }
    
    /// 检查是否今天更新过
    private func isUpdatedToday(_ lastRefreshTime: Date?) -> Bool {
        guard let lastRefresh = lastRefreshTime else { return false }
        
        let calendar = Calendar.current
        let today = Date()
        
        return calendar.isDate(lastRefresh, inSameDayAs: today)
    }
    
    /// 检查特定学者今日是否有刷新
    private func isScholarUpdatedToday(_ scholarId: String) -> Bool {
        let lastKey = "LastRefreshTime_\(scholarId)"
        
        var lastRefreshTime: Date? = nil
        if let appGroup = UserDefaults(suiteName: appGroupIdentifier) {
            lastRefreshTime = appGroup.object(forKey: lastKey) as? Date
        } else {
            lastRefreshTime = UserDefaults.standard.object(forKey: lastKey) as? Date
        }
        
        guard let lastRefresh = lastRefreshTime else { return false }
        
        let calendar = Calendar.current
        let today = Date()
        
        return calendar.isDate(lastRefresh, inSameDayAs: today)
    }
    

    
    /// 基于时间戳检查刷新动画
    private func checkForRefreshAnimation() {
        let lastRefreshKey = "LastRefreshAnimationTime"
        let currentTime = Date().timeIntervalSince1970
        
        // 从UserDefaults获取上次动画时间
        let lastAnimationTime = UserDefaults.standard.double(forKey: lastRefreshKey)
        
        // 如果距离上次动画超过2秒，且有新的刷新时间戳，则播放动画
        if let lastRefreshTime = UserDefaults.standard.object(forKey: "LastRefreshTime") as? Date {
            let refreshTimeStamp = lastRefreshTime.timeIntervalSince1970
            
            // 如果刷新时间比上次动画时间新，则播放动画
            if refreshTimeStamp > lastAnimationTime {
                print("🔄 [Widget] 检测到新的刷新时间戳，播放动画")
                performRefreshAnimation()
                
                // 更新动画时间戳
                UserDefaults.standard.set(currentTime, forKey: lastRefreshKey)
            }
        }
    }
    
    /// 基于时间戳检查切换动画
    private func checkForSwitchAnimation() {
        let lastSwitchKey = "LastSwitchAnimationTime"
        let currentTime = Date().timeIntervalSince1970
        
        let lastAnimationTime = UserDefaults.standard.double(forKey: lastSwitchKey)
        
        // 检查学者切换时间戳
        if let lastSwitchTime = UserDefaults.standard.object(forKey: "LastScholarSwitchTime") as? Date {
            let switchTimeStamp = lastSwitchTime.timeIntervalSince1970
            
            if switchTimeStamp > lastAnimationTime {
                print("🎯 [Widget] 检测到新的切换时间戳，播放动画")
                performSwitchAnimation()
                
                UserDefaults.standard.set(currentTime, forKey: lastSwitchKey)
            }
        }
    }
    
    /// 只检查切换动画 - 使用独立管理器
    private func checkSwitchAnimationOnly() {
        let switchManager = SwitchButtonManager.shared
        let shouldSwitch = switchManager.shouldPlayAnimation()
        
        print("🔍 [Widget] 独立检查切换动画: \(shouldSwitch), 当前状态: \(isSwitching)")
        
        if shouldSwitch && !isSwitching {
            print("🎯 [Widget] ✅ 独立触发切换动画")
            performSwitchAnimation()
        }
    }
    
    /// 只检查刷新动画 - 使用独立管理器（按学者隔离）
    private func checkRefreshAnimationOnly(for scholarId: String?) {
        print("🔍 [Widget] ===== 开始检查刷新动画 =====")
        let refreshManager = RefreshButtonManager.shared
        var shouldRefresh = refreshManager.shouldPlayAnimation()
        // 检查最近触发时间，驱动刷新动画
        let groupID = appGroupIdentifier
        let sid = scholarId ?? (entry.primaryScholar?.id)
        let triggerKey = sid != nil ? "RefreshTriggerTime_\(sid!)" : "RefreshTriggerTime"
        let forceWindow: TimeInterval = 2.5
        var recentTriggered = false
        #if DEBUG
        print("🔎 [Widget] checkRefreshAnimationOnly for sid=\(sid ?? "nil") triggerKey=\(triggerKey)")
        #endif
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            if let trig = appGroupDefaults.object(forKey: triggerKey) as? Date {
                recentTriggered = Date().timeIntervalSince(trig) <= forceWindow
            }
        } else {
            if let trig = UserDefaults.standard.object(forKey: triggerKey) as? Date {
                recentTriggered = Date().timeIntervalSince(trig) <= forceWindow
            }
        }
        #if DEBUG
        print("🔎 [Widget] read recentTriggered=\(recentTriggered)")
        #endif
        if !shouldRefresh && recentTriggered {
            print("🔄 [Widget] 兜底：检测到最近触发时间戳，强制 shouldRefresh = true")
            shouldRefresh = true
        }
        // 兜底：最近触发则立即启动刷新动画
        if recentTriggered {
            startRefreshBlink()
            if !isRefreshing {
                print("🔄 [Widget] 兜底：recentTriggered 命中，立即启动 performRefreshAnimation")
                performRefreshAnimation()
            }
        }
        
        print("🔍 [Widget] 独立检查刷新动画: \(shouldRefresh), 当前状态: \(isRefreshing)")
        
        if shouldRefresh && !isRefreshing {
            print("🔄 [Widget] ✅ 独立触发刷新动画 - 即将调用performRefreshAnimation")
            performRefreshAnimation()
            print("🔄 [Widget] ✅ performRefreshAnimation调用完成")
        } else {
            print("🔄 [Widget] ❌ 不触发刷新动画 - shouldRefresh: \(shouldRefresh), isRefreshing: \(isRefreshing)")
        }
        print("🔍 [Widget] ===== 刷新动画检查结束 =====")
    }
    
    /// 检查刷新完成（按学者）：若 LastRefreshTime_<id> > RefreshStartTime_<id>，则视为完成
    private func checkRefreshCompletion(for scholarId: String?) {
        let groupID = appGroupIdentifier
        var startTime: Date? = nil
        var lastTime: Date? = nil
        let sid = scholarId ?? (entry.primaryScholar?.id)
        let startKey = sid != nil ? "RefreshStartTime_\(sid!)" : "RefreshStartTime"
        let lastKey = sid != nil ? "LastRefreshTime_\(sid!)" : "LastRefreshTime"
        #if DEBUG
        print("🔎 [Widget] checkRefreshCompletion for sid=\(sid ?? "nil") startKey=\(startKey) lastKey=\(lastKey)")
        #endif
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            startTime = appGroupDefaults.object(forKey: startKey) as? Date
            lastTime = appGroupDefaults.object(forKey: lastKey) as? Date
        } else {
            startTime = UserDefaults.standard.object(forKey: startKey) as? Date
            lastTime = UserDefaults.standard.object(forKey: lastKey) as? Date
        }
        // 回落逻辑：若该学者无 lastTime，但全局 last 比 start 新，也视为完成
        let sOpt = startTime
        var lOpt = lastTime
        if lOpt == nil, let sid = sid {
            let global = (UserDefaults(suiteName: groupID)?.object(forKey: "LastRefreshTime") as? Date) ?? (UserDefaults.standard.object(forKey: "LastRefreshTime") as? Date)
            print("🔎 [Widget] fallback check: globalLast=\(String(describing: global)) start=\(String(describing: sOpt))")
            if let g = global, let s = sOpt, g > s {
                lOpt = global
                // 回写学者 last
                if let appGroupDefaults = UserDefaults(suiteName: groupID) {
                    appGroupDefaults.set(g, forKey: "LastRefreshTime_\(sid)")
                    appGroupDefaults.synchronize()
                }
                UserDefaults.standard.set(g, forKey: "LastRefreshTime_\(sid)")
                print("✅ [Widget] 使用全局Last回写完成: sid=\(sid) last=\(g)")
            }
        }
        #if DEBUG
        print("🔎 [Widget] completion compare: start=\(String(describing: sOpt)) last=\(String(describing: lOpt))")
        #endif
        // A. 标准路径：存在 start 并且 last > start
        if let s = sOpt, let l = lOpt, l > s {
            // 刷新完成：复位进行中与闪烁
            stopRefreshBlink()
            isRefreshing = false
            
            // 🎯 更新：刷新完成即刻切换为对勾 - 避免重复设置
            if !self.showRefreshAck {
                self.showRefreshAck = true
                self.saveRefreshAckState(true, for: self.currentScholarId)
                
                // 清除动画活跃标记
                let animationKey = "RefreshAnimationActive_\(self.currentScholarId ?? "default")"
                UserDefaults.standard.removeObject(forKey: animationKey)
                
                print("✅ [Widget] 刷新完成，立即显示对勾")
            }
            
            print("✅ [Widget] 检测到刷新完成")
            // 🎯 延迟清理标记（后台），不阻塞对勾显示
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let appGroupDefaults = UserDefaults(suiteName: groupID) {
                    if let sid = sid {
                        appGroupDefaults.removeObject(forKey: "RefreshStartTime_\(sid)")
                        appGroupDefaults.removeObject(forKey: "RefreshTriggerTime_\(sid)")
                    }
                    appGroupDefaults.removeObject(forKey: "RefreshTriggerTime")
                    appGroupDefaults.synchronize()
                    WidgetCenter.shared.reloadAllTimelines()
                } else {
                    if let sid = sid {
                        UserDefaults.standard.removeObject(forKey: "RefreshStartTime_\(sid)")
                        UserDefaults.standard.removeObject(forKey: "RefreshTriggerTime_\(sid)")
                    }
                    UserDefaults.standard.removeObject(forKey: "RefreshTriggerTime")
                    WidgetCenter.shared.reloadAllTimelines()
                }
                print("✅ [Widget] 标准路径：延迟清理标记完成")
            }
            return
        }
        // B. 兜底路径：无 start 但最近有 last（延长到5s 内），也判定完成
        if let l = lOpt {
            if Date().timeIntervalSince(l) <= 5.0 { // 从1.5改为5.0秒
                stopRefreshBlink()
                isRefreshing = false
                
                // 🎯 更新：刷新完成即刻切换为对勾（兜底路径）- 避免重复设置
                if !self.showRefreshAck {
                    self.showRefreshAck = true
                    self.saveRefreshAckState(true, for: self.currentScholarId)
                    
                    // 清除动画活跃标记
                    let animationKey = "RefreshAnimationActive_\(self.currentScholarId ?? "default")"
                    UserDefaults.standard.removeObject(forKey: animationKey)
                    
                    print("✅ [Widget] 刷新完成，立即显示对勾(兜底)")
                }
                
                // 🎯 延迟清除标记（后台），不阻塞对勾显示
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if let appGroupDefaults = UserDefaults(suiteName: groupID) {
                        if let sid = sid {
                            appGroupDefaults.removeObject(forKey: "RefreshStartTime_\(sid)")
                            appGroupDefaults.removeObject(forKey: "RefreshTriggerTime_\(sid)")
                        }
                        appGroupDefaults.removeObject(forKey: "RefreshTriggerTime")
                        appGroupDefaults.synchronize()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    if let sid = sid {
                        UserDefaults.standard.removeObject(forKey: "RefreshStartTime_\(sid)")
                        UserDefaults.standard.removeObject(forKey: "RefreshTriggerTime_\(sid)")
                    }
                    UserDefaults.standard.removeObject(forKey: "RefreshTriggerTime")
                    WidgetCenter.shared.reloadAllTimelines()
                    print("✅ [Widget] 兜底完成：延迟清理标记完成")
                }
                #if DEBUG
                print("✅ [Widget] 兜底完成：last 新近写入，已显示对勾")
                #endif
            }
        }
    }

    private func startRefreshBlink() {
        // 简单闪烁：切换布尔，依赖 WidgetKit 触发多次渲染可能受限，但尽量呈现
        refreshBlinkOn = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshBlinkOn.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            startRefreshBlink()
        }
    }

    private func stopRefreshBlink() {
        refreshBlinkOn = false
    }

    /// 读取可配置的超时时长（秒）。默认 90，可通过 App Group 或标准存储中的 `WidgetRefreshTimeoutSeconds` 覆盖（范围30~600）。
    private func refreshTimeoutSeconds() -> TimeInterval {
        let key = "WidgetRefreshTimeoutSeconds"
        let minV: TimeInterval = 30
        let maxV: TimeInterval = 600
        var value: TimeInterval = 90
        if let appGroup = UserDefaults(suiteName: appGroupIdentifier), appGroup.object(forKey: key) != nil {
            value = TimeInterval(appGroup.integer(forKey: key))
        } else if UserDefaults.standard.object(forKey: key) != nil {
            value = TimeInterval(UserDefaults.standard.integer(forKey: key))
        }
        if value < minV { return minV }
        if value > maxV { return maxV }
        return value
    }



    /// 读取 App Group 与标准存储的刷新时间戳信息
    private func getRefreshTimestamps(for scholarId: String?) -> (inProgress: Bool, start: Date?, last: Date?) {
        let groupID = appGroupIdentifier
        var inProgress = false
        var startTime: Date? = nil
        var lastTime: Date? = nil
        let sid = scholarId ?? (entry.primaryScholar?.id)
        let inProgressKey = sid != nil ? "RefreshInProgress_\(sid!)" : "RefreshInProgress"
        let startKey = sid != nil ? "RefreshStartTime_\(sid!)" : "RefreshStartTime"
        let lastKey = sid != nil ? "LastRefreshTime_\(sid!)" : "LastRefreshTime"
        if let appGroupDefaults = UserDefaults(suiteName: groupID) {
            inProgress = appGroupDefaults.bool(forKey: inProgressKey)
            startTime = appGroupDefaults.object(forKey: startKey) as? Date
            lastTime = appGroupDefaults.object(forKey: lastKey) as? Date
        } else {
            inProgress = UserDefaults.standard.bool(forKey: inProgressKey)
            startTime = UserDefaults.standard.object(forKey: startKey) as? Date
            lastTime = UserDefaults.standard.object(forKey: lastKey) as? Date
        }
        print("🔎 [Widget] getTS sid=\(sid ?? "nil") in=\(inProgress) start=\(String(describing: startTime)) last=\(String(describing: lastTime))")
        return (inProgress, startTime, lastTime)
    }



    /// 刷新调试状态文本与颜色（Idle/InProg/Done/Timeout）
    private func refreshDebugStatus(for scholarId: String?) -> (text: String, color: Color) {
        let (inProgress, startOpt, lastOpt) = getRefreshTimestamps(for: scholarId)
        let now = Date()
        let timeout: TimeInterval = refreshTimeoutSeconds()
        if let s = startOpt, let l = lastOpt, l > s {
            return ("Done", .green)
        }
        if inProgress, let s = startOpt {
            if now.timeIntervalSince(s) > timeout {
                return ("Timeout", .orange)
            }
            return ("InProg", .yellow)
        }
        return ("Idle", .secondary)
    }

    /// 是否显示调试状态角标（默认开启，可通过 App Group 键关闭）
    private func debugOverlayEnabled() -> Bool {
        let key = "WidgetDebugOverlayEnabled"
        if let appGroup = UserDefaults(suiteName: appGroupIdentifier) {
            if appGroup.object(forKey: key) != nil {
                return appGroup.bool(forKey: key)
            }
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return true
    }
    
    /// 执行切换视觉反馈（高亮+脉冲光环）
    private func performSwitchAnimation() {
        guard !isSwitching else { return }

        isSwitching = true
        print("🎯 [Widget] 切换反馈开始（高亮+脉冲） isSwitching=true")
        // 背景高亮开启
        self.switchHighlight = true
        // 启动脉冲光环动画
        self.showSwitchPulse = true
        self.switchPulseScale = 0.7
        self.switchPulseOpacity = 0.6
        withAnimation(.easeOut(duration: 0.4)) {
            self.switchPulseScale = 1.25
            self.switchPulseOpacity = 0.0
        }
        // 结束脉冲与高亮（无条件复位，避免亮度残留）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.isSwitching = false
            self.showSwitchPulse = false
            self.switchPulseScale = 1.0
            self.switchPulseOpacity = 0.0
            self.switchHighlight = false
            print("🎯 [Widget] 结束高亮 isSwitching=false（脉冲停止, 背景复位）")
        }
    }
    

    
    /// 执行刷新动画 - 优化版本
    private func performRefreshAnimation() {
        #if DEBUG
        print("🔄 [Widget] ===== performRefreshAnimation 开始执行 =====")
        print("🔄 [Widget] 当前 isRefreshing 状态: \(isRefreshing)")
        #endif
        
        // 🎯 双重保护：检查本地状态和持久化状态
        let animationKey = "RefreshAnimationActive_\(currentScholarId ?? "default")"
        let isAnimationActive = UserDefaults.standard.bool(forKey: animationKey)
        
        guard !isRefreshing && !isAnimationActive else { 
            #if DEBUG
            print("🔄 [Widget] ⚠️ 刷新动画已在进行，跳过 (local: \(isRefreshing), persistent: \(isAnimationActive))")
            #endif
            return 
        }
        
        // 立即设置持久化标记，防止重复调用
        UserDefaults.standard.set(true, forKey: animationKey)
        
        // 🎯 性能优化：立即设置所有状态，减少卡顿
        isRefreshing = true
        showRefreshAck = false  // 🎯 清除对号状态，开始新的刷新
        
        #if DEBUG
        print("🔄 [Widget] 设置 isRefreshing = true")
        print("🔄 [Widget] 开始刷新动画")
        #endif
        

        
        // 🎯 性能优化：在主线程启动UI动画
        DispatchQueue.main.async {
            // 🚫 不再清除对勾状态，由Intent负责设置
            self.startRefreshBlink()
        }

        // 🎯 Intent已立即设置对勾状态，不需要延迟检查
        // Widget只需读取状态即可
        
        // 不触发切换式效果
        // 不在此处复位，由数据到达后复位
    }
    
    // 🎯 持久化对号状态，避免Widget重新加载时丢失
    private func saveRefreshAckState(_ state: Bool, for scholarId: String?) {
        let key = scholarId != nil ? "ShowRefreshAck_\(scholarId!)" : "ShowRefreshAck"
        
        if let appGroup = UserDefaults(suiteName: appGroupIdentifier) {
            appGroup.set(state, forKey: key)
            appGroup.synchronize()
            print("💾 [Widget] 保存对号状态: \(key) = \(state) (App Group)")
        } else {
            UserDefaults.standard.set(state, forKey: key)
            print("💾 [Widget] 保存对号状态: \(key) = \(state) (Standard)")
        }
    }
    
    // 🎯 从持久化存储中加载对号状态（与当前学者绑定）
    private func loadRefreshAckState() {
        let scholarId = currentScholarId
        let key = scholarId != nil ? "ShowRefreshAck_\(scholarId!)" : "ShowRefreshAck"
        
        // 🎯 修复：默认显示刷新按钮，除非明确保存了对勾状态
        var savedState = false
        var lastTimeForScholar: Date? = nil
        if let appGroup = UserDefaults(suiteName: appGroupIdentifier) {
            savedState = appGroup.bool(forKey: key)
            print("📖 [Widget] 加载对号状态: \(key) = \(savedState) (App Group)")
            if let sid = scholarId {
                lastTimeForScholar = appGroup.object(forKey: "LastRefreshTime_\(sid)") as? Date
            }
        } else {
            savedState = UserDefaults.standard.bool(forKey: key)
            print("📖 [Widget] 加载对号状态: \(key) = \(savedState) (Standard)")
            if let sid = scholarId {
                lastTimeForScholar = UserDefaults.standard.object(forKey: "LastRefreshTime_\(sid)") as? Date
            }
        }
        
        // 🎯 简化逻辑：基于时间控制对勾显示
        if savedState, let last = lastTimeForScholar {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed > 6.0 {
                showRefreshAck = false
                saveRefreshAckState(false, for: scholarId)
                print("🧹 [Widget] 对勾超时(>6s)，恢复为刷新按钮")
            } else {
                showRefreshAck = true
                print("🔄 [Widget] 保留对勾(\(String(format: "%.1f", elapsed))s 内)")
            }
        } else {
            showRefreshAck = false
            if savedState == true { saveRefreshAckState(false, for: scholarId) }
            print("🔄 [Widget] 默认显示刷新按钮")
        }
    }
}

/// 🎯 中尺寸：学者影响力榜单 - 乔布斯式简洁对比
struct MediumWidgetView: View {
    let entry: CiteTrackWidgetEntry
    
    var body: some View {
        if !entry.scholars.isEmpty {
            VStack(spacing: 2) {
                // 顶部：标题和总览 - 优化布局
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("academic_influence".widgetLocalized)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        
                        Text("Top \(min(entry.scholars.count, 3)) " + "top_scholars".widgetLocalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 8)
                    
                    // 总引用数显示 - 优化大小
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(entry.totalCitations)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("total_citations_label".widgetLocalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 10)
                
                // 中心：排行榜 - 紧凑设计
                VStack(spacing: 2) {
                    ForEach(Array(entry.scholars.prefix(3).enumerated()), id: \.element.id) { index, scholar in
                        HStack(spacing: 10) {
                            // 排名徽章 - 缩小尺寸
                            ZStack {
                                Circle()
                                    .fill(rankColor(index))
                                    .frame(width: 20, height: 20)
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            // 学者信息 - 优化布局
                            VStack(alignment: .leading, spacing: 1) {
                                Text(scholar.displayName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                if let institution = scholar.institution {
                                    Text(institution)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            
                            Spacer(minLength: 4)
                            
                            // 引用数和趋势 - 紧凑设计
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(scholar.citations ?? 0)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                
                                // 趋势指示器 - 缩小尺寸
                                HStack(spacing: 1) {
                                    Text(scholar.citationTrend.symbol)
                                        .font(.caption2)
                                    Text(scholar.citationTrend.text)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(scholar.citationTrend.color)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 0)
                        
                        // 分隔线（除了最后一个） - 缩小间距
                        if index < min(entry.scholars.count, 3) - 1 {
                            Divider()
                                .padding(.horizontal, 10)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                
                // 底部：时间戳 - 优化布局
                if let lastRefresh = entry.lastRefreshTime {
                    Text("updated_at".widgetLocalized + " \(formatTime(lastRefresh))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.bottom, 4)
                        .padding(.horizontal, 10)
                }
            }
            .containerBackground(widgetBackgroundColor(for: entry.widgetTheme), for: .widget)
            .widgetURL(URL(string: "citetrack://scholars"))
            
        } else {
            // 空状态：引导添加学者 - 优化布局
            VStack(spacing: 16) {
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "trophy.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange.opacity(0.7))
                    
                    VStack(spacing: 6) {
                        Text("academic_ranking".widgetLocalized)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .minimumScaleFactor(0.8)
                        Text("add_scholars_to_track".widgetLocalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .minimumScaleFactor(0.8)
                    }
                }
                
                // Spacer()
                
                // 底部提示：轻触打开App
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.6))
                    
                    Text("tap_to_open_app".widgetLocalized)
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.6))
                }
                .padding(.bottom, 6)
            }
            .padding(6)
            .containerBackground(widgetBackgroundColor(for: entry.widgetTheme), for: .widget)
            .widgetURL(URL(string: "citetrack://add-scholar"))
        }
    }
    
    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .orange  // 金牌
        case 1: return .gray    // 银牌
        case 2: return .brown   // 铜牌
        default: return .blue
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// 🎯 大尺寸：学术影响力仪表板 - 乔布斯式完整洞察
struct LargeWidgetView: View {
    let entry: CiteTrackWidgetEntry
    
    var body: some View {
        if !entry.scholars.isEmpty {
            VStack(spacing: 6) {
                // 顶部：仪表板标题和关键指标 - 紧凑设计
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("academic_influence".widgetLocalized + " " + "dashboard".widgetLocalized)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            
                            Text("tracking_scholars".widgetLocalized + " \(entry.scholars.count) " + "scholars".widgetLocalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer(minLength: 8)
                        
                        // 时间指示器 - 优化尺寸
                        if let lastRefresh = entry.lastRefreshTime {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("latest_data".widgetLocalized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Text(formatTime(lastRefresh))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .minimumScaleFactor(0.8)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    // 核心指标卡片 - 缩小尺寸
                    HStack(spacing: 8) {
                        // 总引用数卡片
                        VStack(spacing: 2) {
                            Text("\(entry.totalCitations)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Text("total_citations_label".widgetLocalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                        
                        // 平均引用数卡片
                        VStack(spacing: 2) {
                            Text("\(entry.totalCitations / max(entry.scholars.count, 1))")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Text("average_citations_label".widgetLocalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                        
                        // 顶尖学者指标
                        if let topScholar = entry.scholars.first {
                            VStack(spacing: 2) {
                                Text("\(topScholar.citations ?? 0)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                Text("highest_citations_label".widgetLocalized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 12)
                
                // 中心：学者卡片网格 - 紧凑设计
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                    ForEach(Array(entry.scholars.prefix(4).enumerated()), id: \.element.id) { index, scholar in
                        VStack(alignment: .leading, spacing: 4) {
                            // 学者头部信息 - 缩小尺寸
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(scholar.displayName)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    
                                    if let institution = scholar.institution {
                                        Text(institution)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                }
                                
                                Spacer(minLength: 4)
                                
                                // 排名徽章 - 缩小尺寸
                                Text("#\(index + 1)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(rankColor(index))
                                    .cornerRadius(3)
                            }
                            
                            // 核心数据 - 缩小尺寸
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(scholar.citations ?? 0)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .minimumScaleFactor(0.8)
                                        .lineLimit(1)
                                    
                                    Text("citations_label".widgetLocalized)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer(minLength: 4)
                                
                                // 趋势指示器 - 缩小尺寸
                                VStack(alignment: .trailing, spacing: 1) {
                                    HStack(spacing: 1) {
                                        Text(scholar.citationTrend.symbol)
                                            .font(.caption2)
                                        Text(scholar.citationTrend.text)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(scholar.citationTrend.color)
                                    
                                    Text("this_month".widgetLocalized)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 12)
                
                // 底部：数据洞察 - 缩小尺寸
                VStack(spacing: 4) {
                    Divider()
                        .padding(.horizontal, 12)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("data_insights".widgetLocalized)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            let growingScholars = entry.scholars.filter { scholar in
                                switch scholar.citationTrend {
                                case .up: return true
                                default: return false
                                }
                            }.count
                            
                            Text("\(growingScholars) " + "scholars".widgetLocalized + " " + "citation_trend".widgetLocalized)
                                .font(.caption2)
                                .foregroundColor(.green)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        
                        Spacer(minLength: 8)
                        
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("team_performance".widgetLocalized)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            let performance = entry.totalCitations > 1000 ? "performance_excellent".widgetLocalized : entry.totalCitations > 500 ? "performance_good".widgetLocalized : "performance_starting".widgetLocalized
                            Text(performance)
                                .font(.caption2)
                                .foregroundColor(entry.totalCitations > 1000 ? .green : entry.totalCitations > 500 ? .orange : .blue)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .containerBackground(widgetBackgroundColor(for: entry.widgetTheme), for: .widget)
            .widgetURL(URL(string: "citetrack://dashboard"))
            
        } else {
            // 空状态：完整的引导界面 - 优化布局
            VStack(spacing: 12) {
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.blue.opacity(0.6))
                    
                    VStack(spacing: 6) {
                        Text("academic_influence".widgetLocalized + " " + "dashboard".widgetLocalized)
                            .font(.headline)
                            .fontWeight(.bold)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        
                        Text("add_scholars_to_track".widgetLocalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .minimumScaleFactor(0.8)
                    }
                    
                    // 功能预览 - 缩小尺寸
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("realtime_citation_tracking".widgetLocalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.8)
                            Spacer()
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("scholar_ranking_comparison".widgetLocalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.8)
                            Spacer()
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("trend_change_analysis".widgetLocalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.8)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                // Spacer()
                
                // 底部提示：轻触打开App
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.6))
                    
                    Text("tap_to_open_app".widgetLocalized)
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.6))
                }
                .padding(.bottom, 8)
            }
            .padding(10)
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "citetrack://add-scholar"))
        }
    }
    
    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .orange  // 金色
        case 1: return .gray    // 银色
        case 2: return .brown   // 铜色
        default: return .blue
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 独立的按钮管理器
class SwitchButtonManager {
    static let shared = SwitchButtonManager()
    // 使用全局定义的 appGroupIdentifier
    private init() {}
    
    func shouldPlayAnimation() -> Bool {
        // 优先检查App Group
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            let shouldPlay = appGroupDefaults.bool(forKey: "ScholarSwitched")
            if shouldPlay {
                appGroupDefaults.removeObject(forKey: "ScholarSwitched")
                appGroupDefaults.synchronize()
                print("🎯 [SwitchManager] App Group 检测到切换标记，已清除")
                return true
            }
        }
        
        // 回退检查Standard
        let shouldPlay = UserDefaults.standard.bool(forKey: "ScholarSwitched")
        if shouldPlay {
            UserDefaults.standard.removeObject(forKey: "ScholarSwitched")
            print("🎯 [SwitchManager] Standard 检测到切换标记，已清除")
            return true
        }
        
        return false
    }
}

class RefreshButtonManager {
    static let shared = RefreshButtonManager()
    // 使用全局定义的 appGroupIdentifier
    private init() {}
    
    func shouldPlayAnimation() -> Bool {
        print("🔄 [RefreshManager] ===== 开始检查刷新标记 =====")
        
        // 优先检查App Group
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            print("🔄 [RefreshManager] App Group UserDefaults 创建成功")
            let shouldPlay = appGroupDefaults.bool(forKey: "RefreshTriggered")
            print("🔄 [RefreshManager] App Group RefreshTriggered 值: \(shouldPlay)")
            if shouldPlay {
                appGroupDefaults.removeObject(forKey: "RefreshTriggered")
                appGroupDefaults.synchronize()
                print("🔄 [RefreshManager] ✅ App Group 检测到刷新标记，已清除")
                return true
            }
        } else {
            print("🔄 [RefreshManager] ❌ App Group UserDefaults 创建失败")
        }
        
        // 回退检查Standard
        print("🔄 [RefreshManager] 检查 Standard UserDefaults")
        let shouldPlay = UserDefaults.standard.bool(forKey: "RefreshTriggered")
        print("🔄 [RefreshManager] Standard RefreshTriggered 值: \(shouldPlay)")
        if shouldPlay {
            UserDefaults.standard.removeObject(forKey: "RefreshTriggered")
            print("🔄 [RefreshManager] ✅ Standard 检测到刷新标记，已清除")
            return true
        }
        
        print("🔄 [RefreshManager] ❌ 未发现刷新标记")
        print("🔄 [RefreshManager] ===== 刷新标记检查结束 =====")
        return false
    }
}

// MARK: - 小组件按钮管理器（保留兼容性）
class WidgetButtonManager {
    static let shared = WidgetButtonManager()
    // 使用全局定义的 appGroupIdentifier
    
    private init() {}
    
    /// 触发切换动画标记
    func triggerSwitchAnimation() {
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            appGroupDefaults.set(true, forKey: "ScholarSwitched")
        }
        UserDefaults.standard.set(true, forKey: "ScholarSwitched")
    }
    
    /// 触发刷新动画标记
    func triggerRefreshAnimation() {
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            appGroupDefaults.set(true, forKey: "RefreshTriggered")
        }
        UserDefaults.standard.set(true, forKey: "RefreshTriggered")
    }
    
    /// 清除动画标记
    func clearAnimationFlags() {
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            appGroupDefaults.removeObject(forKey: "ScholarSwitched")
            appGroupDefaults.removeObject(forKey: "RefreshTriggered")
        }
        UserDefaults.standard.removeObject(forKey: "ScholarSwitched")
        UserDefaults.standard.removeObject(forKey: "RefreshTriggered")
    }
    
    /// 检查是否需要播放切换动画 - 完全独立版本
    func shouldPlaySwitchAnimation() -> Bool {
        // 优先检查App Group
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            let shouldPlay = appGroupDefaults.bool(forKey: "ScholarSwitched")
            if shouldPlay {
                // 只清除自己的标记，不读取其他标记
                appGroupDefaults.removeObject(forKey: "ScholarSwitched")
                appGroupDefaults.synchronize()
                print("🎯 [ButtonManager] App Group 检测到切换标记，已清除")
                return true
            }
        }
        
        // 回退检查Standard
        let shouldPlay = UserDefaults.standard.bool(forKey: "ScholarSwitched")
        if shouldPlay {
            UserDefaults.standard.removeObject(forKey: "ScholarSwitched")
            print("🎯 [ButtonManager] Standard 检测到切换标记，已清除")
            return true
        }
        
        return false
    }
    
    /// 检查是否需要播放刷新动画 - 完全独立版本
    func shouldPlayRefreshAnimation() -> Bool {
        // 优先检查App Group
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            let shouldPlay = appGroupDefaults.bool(forKey: "RefreshTriggered")
            if shouldPlay {
                // 只清除自己的标记，不读取其他标记
                appGroupDefaults.removeObject(forKey: "RefreshTriggered")
                appGroupDefaults.synchronize()
                print("🔄 [ButtonManager] App Group 检测到刷新标记，已清除")
                return true
            }
        }
        
        // 回退检查Standard
        let shouldPlay = UserDefaults.standard.bool(forKey: "RefreshTriggered")
        if shouldPlay {
            UserDefaults.standard.removeObject(forKey: "RefreshTriggered")
            print("🔄 [ButtonManager] Standard 检测到刷新标记，已清除")
            return true
        }
        
        return false
    }
}

// MARK: - 自定义按钮样式，提供视觉反馈
struct WidgetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 增强版按钮样式 - 更丰富的视觉反馈
struct EnhancedWidgetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Widget Configuration
struct CiteTrackWidget: Widget {
    let kind: String = "CiteTrackWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CiteTrackWidgetProvider()) { entry in
            CiteTrackWidgetView(entry: entry)
        }
        .configurationDisplayName("CiteTrack")
        .description("跟踪学者的引用数据和学术影响力")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview
struct CiteTrackWidget_Previews: PreviewProvider {
    static var previews: some View {
        // 空状态预览
        let emptyEntry = CiteTrackWidgetEntry(
            date: Date(),
            scholars: [],
            primaryScholar: nil,
            totalCitations: 0,
            lastRefreshTime: nil
        )
        
        let sampleEntry = CiteTrackWidgetEntry(
            date: Date(),
            scholars: [
                WidgetScholarInfo(id: "1", displayName: "Geoffrey Edward Hinton", institution: "University of Toronto", citations: 234567, hIndex: 145, lastUpdated: Date(), weeklyGrowth: 5, monthlyGrowth: 523, quarterlyGrowth: 1278),
                WidgetScholarInfo(id: "2", displayName: "Yann Andre LeCun", institution: "New York University", citations: 187654, hIndex: 128, lastUpdated: Date(), weeklyGrowth: 3, monthlyGrowth: 415, quarterlyGrowth: 942)
            ],
            primaryScholar: WidgetScholarInfo(id: "1", displayName: "Geoffrey Edward Hinton", institution: "University of Toronto", citations: 234567, hIndex: 145, lastUpdated: Date(), weeklyGrowth: 5, monthlyGrowth: 523, quarterlyGrowth: 1278),
            totalCitations: 422221,
            lastRefreshTime: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) // 2小时前刷新（今天）
        )
        
        Group {
            // 空状态预览
            CiteTrackWidgetView(entry: emptyEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Empty State - Small")
            
            // Medium/Large previews temporarily disabled
            
            // 有数据状态预览
            CiteTrackWidgetView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("With Data - Small")
            
            // Medium/Large previews temporarily disabled
        }
    }
}





@main
struct CiteTrackWidgets: WidgetBundle {
    var body: some Widget {
        CiteTrackWidget()
    }
}