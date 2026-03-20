import Foundation
import SwiftUI
import Network

// MARK: - 应用初始化服务
/// 负责处理应用第一次启动时的初始化任务
class AppInitializationService: ObservableObject {
    static let shared = AppInitializationService()
    
    @Published var isInitializing = false
    @Published var initializationProgress: String = ""
    @Published var isFirstLaunch: Bool = false
    
    private let dataManager = DataManager.shared
    private let googleScholarService = GoogleScholarService()
    
    private init() {
        checkFirstLaunch()
    }
    
    // MARK: - 首次启动检查
    
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
        isFirstLaunch = !hasLaunchedBefore
        
        if isFirstLaunch {
            print("🚀 [AppInitialization] \("debug_first_launch_detected".localized)")
        } else {
            print("ℹ️ [AppInitialization] \("debug_not_first_launch".localized)")
        }
    }
    
    // MARK: - 初始化流程
    
    /// 执行完整的初始化流程
    func performInitialization() async {
        guard isFirstLaunch else {
            print("ℹ️ [AppInitialization] \("debug_skip_initialization".localized)")
            return
        }
        
        await MainActor.run {
            isInitializing = true
            initializationProgress = "debug_init_starting".localized
        }
        
        // 1. 等待网络连接
        await waitForNetworkConnection()
        
        // 2. 导入初始化数据
        await importInitialData()
        
        // 3. 更新所有学者数据
        // ❌ 注释掉自动更新：首次安装时不应该自动获取数据，应该由用户手动触发
        // await updateAllScholars()
        
        // 4. 标记初始化完成
        await markInitializationComplete()
        
        await MainActor.run {
            isInitializing = false
            initializationProgress = "debug_init_complete_init".localized
        }
        
        print("✅ [AppInitialization] \("debug_init_flow_complete".localized)")
    }
    
    // MARK: - 网络连接检查
    
    private func waitForNetworkConnection() async {
        await MainActor.run {
            initializationProgress = "debug_init_check_network".localized
        }
        
        // 按用户要求：取消首次访问 https://scholar.google.com 的网络检查，直接跳过
        print("ℹ️ [AppInitialization] Skip initial network probe per user setting")
    }
    
    // MARK: - 数据导入
    
    private func importInitialData() async {
        await MainActor.run {
            initializationProgress = "debug_init_import_data".localized
        }
        
        guard let jsonURL = Bundle.main.url(forResource: "citetrack_init", withExtension: "json") else {
            print("❌ [AppInitialization] \("debug_init_file_not_found".localized)")
            return
        }
        
        do {
            let jsonData = try Data(contentsOf: jsonURL)
            let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] ?? []
            
            print("📊 [AppInitialization] \(String(format: "debug_init_data_found".localized, jsonArray.count))")
            
            // 解析并导入数据
            var scholars: [Scholar] = []
            var historyEntries: [CitationHistory] = []
            
            for entry in jsonArray {
                guard let scholarId = entry["scholarId"] as? String,
                      let scholarName = entry["scholarName"] as? String,
                      let citationCount = entry["citationCount"] as? Int,
                      let timestampString = entry["timestamp"] as? String else {
                    continue
                }
                
                // 解析时间戳
                let formatter = ISO8601DateFormatter()
                guard let timestamp = formatter.date(from: timestampString) else {
                    continue
                }
                
                // 创建学者对象
                var scholar = Scholar(id: scholarId, name: scholarName)
                scholar.citations = citationCount
                scholar.lastUpdated = timestamp
                
                // 避免重复添加学者
                if !scholars.contains(where: { $0.id == scholarId }) {
                    scholars.append(scholar)
                }
                
                // 创建历史记录
                let history = CitationHistory(
                    scholarId: scholarId,
                    citationCount: citationCount,
                    timestamp: timestamp
                )
                historyEntries.append(history)
            }
            
            // 导入学者数据
            let scholarsToImport = scholars
            for scholar in scholarsToImport {
                await MainActor.run {
                    dataManager.addScholar(scholar)
                }
            }
            
            // 导入历史数据
            let historyDataToImport = historyEntries
            await MainActor.run {
                dataManager.importHistoryData(historyDataToImport)
            }
            
            print("✅ [AppInitialization] \(String(format: "debug_init_import_success".localized, scholars.count, historyEntries.count))")
            
        } catch {
            print("❌ [AppInitialization] \(String(format: "debug_init_import_failed".localized, error.localizedDescription))")
            // 不抛出错误，继续执行
        }
    }
    
    // MARK: - 学者数据更新
    
    private func updateAllScholars() async {
        await MainActor.run {
            initializationProgress = "debug_init_update_scholars".localized
        }
        
        let scholars = dataManager.scholars
        guard !scholars.isEmpty else {
            print("ℹ️ [AppInitialization] \("debug_init_no_scholars".localized)")
            return
        }
        
        print("🔄 [AppInitialization] \(String(format: "debug_init_start_update".localized, scholars.count))")
        
        // 🚀 使用统一协调器并行更新所有学者
        // 协调器内部会管理任务队列和速率限制
        var successCount = 0
        for scholar in scholars {
            await MainActor.run {
                initializationProgress = String(format: "debug_init_update_scholar".localized, scholar.name)
            }

            // 如果数据仍然新鲜（1小时内），跳过网络请求
            let isFresh = await MainActor.run {
                UnifiedCacheManager.shared.isDataFresh(scholarId: scholar.id)
            }
            if isFresh {
                print("⏳ [AppInitialization] Data still fresh, skipping: \(scholar.name)")
                successCount = min(successCount + 1, Int.max - 1)
                continue
            }

            // 使用统一协调器获取学者数据（中等优先级，初始化过程）
            await CitationFetchCoordinator.shared.fetchScholarComprehensive(
                scholarId: scholar.id,
                priority: .medium
            )
            
            // 初始化引用变化通知服务的引用量记录
            // 注意：需要确保 CitationChangeNotificationService.swift 已添加到 Xcode 项目
            // Task { @MainActor in
            //     let service = CitationChangeNotificationService.shared
            //     service.initializeCitationCounts(for: scholar.id)
            // }
            
            // 从统一缓存获取更新后的数据（需要在主线程访问）
            let basicInfo = await MainActor.run {
                UnifiedCacheManager.shared.getScholarBasicInfo(scholarId: scholar.id)
            }
            
            if let basicInfo = basicInfo {
                // 更新学者信息
                var updatedScholar = scholar
                updatedScholar.name = basicInfo.name
                updatedScholar.citations = basicInfo.citations
                updatedScholar.lastUpdated = basicInfo.lastUpdated
                
                // 复制为不可变常量，避免在并发闭包中捕获可变引用
                let scholarToUpdate = updatedScholar
                
                // 在主线程更新数据管理器
                await MainActor.run {
                    dataManager.updateScholar(scholarToUpdate)
                    
                    // 添加引用历史记录
                    let history = CitationHistory(scholarId: scholar.id, citationCount: basicInfo.citations)
                    dataManager.addHistory(history)
                }
                
                // 使用安全的加法，防止溢出
                successCount = min(successCount + 1, Int.max - 1)
                print("✅ [AppInitialization] \(String(format: "debug_init_scholar_success".localized, basicInfo.name, basicInfo.citations))")
            } else {
                print("❌ [AppInitialization] \(String(format: "debug_init_scholar_failed".localized, scholar.name, "无法从缓存获取学者信息"))")
            }
        }
        
        print("✅ [AppInitialization] \(String(format: "debug_init_update_complete".localized, successCount, scholars.count))")
    }
    
    // MARK: - 完成初始化
    
    private func markInitializationComplete() async {
        await MainActor.run {
            initializationProgress = "debug_init_finalize".localized
        }
        
        UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        await MainActor.run {
            isFirstLaunch = false
        }
        
        print("✅ [AppInitialization] \("debug_init_mark_complete".localized)")
    }
}

