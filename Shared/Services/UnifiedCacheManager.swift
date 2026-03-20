import Foundation
import Combine

// MARK: - 统一数据快照模型
/// 从一次 Google Scholar 访问中能获取的所有信息
public struct ScholarDataSnapshot {
    public let scholarId: String
    public let timestamp: Date
    
    // 学者基本信息
    public let scholarName: String?
    public let totalCitations: Int?
    public let hIndex: Int?
    public let i10Index: Int?
    
    // 论文列表（可能只是部分，取决于排序和分页）
    public let publications: [ScholarPublication]
    public let sortBy: String  // "total", "pubdate", "title"
    public let startIndex: Int  // 分页起始索引
    
    // 元数据
    public let source: DataSource
    
    public enum DataSource: String, Codable {
        case scholarProfile = "scholar_profile"  // 学者主页
        case whoCiteMe = "who_cite_me"          // Who Cite Me 页面
        case dashboard = "dashboard"             // Dashboard 刷新
        case autoUpdate = "auto_update"          // 自动更新
        case widget = "widget"                   // Widget 刷新
    }
    
    public init(
        scholarId: String,
        timestamp: Date = Date(),
        scholarName: String? = nil,
        totalCitations: Int? = nil,
        hIndex: Int? = nil,
        i10Index: Int? = nil,
        publications: [ScholarPublication],
        sortBy: String,
        startIndex: Int,
        source: DataSource
    ) {
        self.scholarId = scholarId
        self.timestamp = timestamp
        self.scholarName = scholarName
        self.totalCitations = totalCitations
        self.hIndex = hIndex
        self.i10Index = i10Index
        self.publications = publications
        self.sortBy = sortBy
        self.startIndex = startIndex
        self.source = source
    }
}

// MARK: - 统一缓存管理器
/// 全局统一的缓存管理器，负责：
/// 1. 存储所有从 Google Scholar 获取的数据
/// 2. 为不同的 UI 模块提供数据视图
/// 3. 检测和通知数据变化
@MainActor
public class UnifiedCacheManager: ObservableObject {
    public static let shared = UnifiedCacheManager()
    
    // MARK: - Published Properties（UI 订阅用）
    
    /// 学者基本信息缓存（scholarId -> 最新的基本信息）
    @Published public private(set) var scholarBasicInfo: [String: ScholarBasicInfo] = [:]
    
    /// 论文列表缓存（scholarId -> sortBy -> 所有页面的论文）
    @Published public private(set) var scholarPublications: [String: [String: [ScholarPublication]]] = [:]
    
    /// 引用文章缓存（clusterId -> sortByDate -> 所有页面的引用文章）
    @Published public private(set) var citingPapersCache: [String: [String: [CitingPaper]]] = [:]
    
    /// 数据变化通知（用于 Who Cite Me 等模块监听变化）
    public let dataChangePublisher = PassthroughSubject<DataChangeEvent, Never>()
    
    // MARK: - Private Storage
    
    /// 原始数据快照存储（按时间顺序，用于审计和回溯）
    private var dataSnapshots: [String: [ScholarDataSnapshot]] = [:]  // scholarId -> snapshots
    
    /// 缓存过期时间（7天 — 学术引用数据变化缓慢，延长缓存可大幅减少 Google Scholar 请求）
    private let cacheExpirationInterval: TimeInterval = 7 * 24 * 60 * 60
    
    /// 持久化存储键
    private let persistenceKey = "UnifiedCacheManager_Data"
    
    private init() {
        print("📦 [UnifiedCache] Initialized")
        // 从持久化存储加载数据
        loadPersistedData()
    }
    
    // MARK: - 持久化
    
    /// 从持久化存储加载数据
    private func loadPersistedData() {
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
        guard let data = appGroupDefaults.data(forKey: persistenceKey) else {
            print("📦 [UnifiedCache] No persisted data found, starting fresh")
            return
        }

        let persisted: PersistedCacheData
        do {
            persisted = try JSONDecoder().decode(PersistedCacheData.self, from: data)
        } catch {
            print("❌ [UnifiedCache] Failed to decode persisted data: \(error.localizedDescription). Clearing corrupted cache.")
            clearPersistedData()
            return
        }
        
        // 检查缓存是否过期
        let now = Date()
        if let lastSaved = persisted.lastSaved,
           now.timeIntervalSince(lastSaved) > cacheExpirationInterval {
            print("📦 [UnifiedCache] Persisted data expired, clearing")
            clearPersistedData()
            return
        }
        
        // 恢复学者基本信息
        scholarBasicInfo = persisted.scholarBasicInfo
        
        // 恢复论文列表
        scholarPublications = persisted.scholarPublications
        
        // 恢复引用文章缓存
        citingPapersCache = persisted.citingPapersCache
        
        let publicationCount = scholarPublications.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        let citingPapersCount = citingPapersCache.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        print("📦 [UnifiedCache] Loaded persisted data: \(scholarBasicInfo.count) scholars, \(publicationCount) publications, \(citingPapersCount) citing papers")
    }
    
    /// 保存数据到持久化存储
    private func persistData() {
        let persisted = PersistedCacheData(
            scholarBasicInfo: scholarBasicInfo,
            scholarPublications: scholarPublications,
            citingPapersCache: citingPapersCache,
            lastSaved: Date()
        )
        
        let data: Data
        do {
            data = try JSONEncoder().encode(persisted)
        } catch {
            print("❌ [UnifiedCache] Failed to encode data for persistence: \(error.localizedDescription)")
            return
        }
        
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
        appGroupDefaults.set(data, forKey: persistenceKey)
        appGroupDefaults.synchronize()
        print("💾 [UnifiedCache] Persisted data to disk")
    }
    
    /// 清除持久化数据
    private func clearPersistedData() {
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
        appGroupDefaults.removeObject(forKey: persistenceKey)
        appGroupDefaults.synchronize()
    }
    
    /// 持久化的缓存数据结构
    private struct PersistedCacheData: Codable {
        let scholarBasicInfo: [String: ScholarBasicInfo]
        let scholarPublications: [String: [String: [ScholarPublication]]]
        let citingPapersCache: [String: [String: [CitingPaper]]]  // clusterId -> sortByDate -> papers
        let lastSaved: Date?
    }
    
    // MARK: - 数据变化事件
    
    public enum DataChangeEvent {
        case scholarInfoUpdated(scholarId: String, oldCitations: Int?, newCitations: Int?)
        case publicationsUpdated(scholarId: String, sortBy: String, count: Int)
        case publicationsChanged(scholarId: String, changes: CitationCacheService.PublicationChanges)
        case newPublicationsDetected(scholarId: String, newCount: Int)
        case citingPapersUpdated(clusterId: String, count: Int)
    }
    
    // MARK: - 学者基本信息
    
    public struct ScholarBasicInfo: Codable {
        public let scholarId: String
        public let name: String
        public let citations: Int
        public let hIndex: Int?
        public let i10Index: Int?
        public let lastUpdated: Date
        public let source: ScholarDataSnapshot.DataSource
        
        public init(
            scholarId: String,
            name: String,
            citations: Int,
            hIndex: Int? = nil,
            i10Index: Int? = nil,
            lastUpdated: Date = Date(),
            source: ScholarDataSnapshot.DataSource
        ) {
            self.scholarId = scholarId
            self.name = name
            self.citations = citations
            self.hIndex = hIndex
            self.i10Index = i10Index
            self.lastUpdated = lastUpdated
            self.source = source
        }
    }
    
    // MARK: - 核心方法：保存数据快照
    
    /// 保存从 Google Scholar 获取的数据快照
    /// 这是唯一的数据入口，所有从 Google Scholar 获取的数据都应该通过这个方法保存
    public func saveDataSnapshot(_ snapshot: ScholarDataSnapshot) {
        print("📥 [UnifiedCache] Saving snapshot for \(snapshot.scholarId), source: \(snapshot.source.rawValue), \(snapshot.publications.count) publications")
        
        // 1. 保存原始快照
        if dataSnapshots[snapshot.scholarId] == nil {
            dataSnapshots[snapshot.scholarId] = []
        }
        dataSnapshots[snapshot.scholarId]?.append(snapshot)
        
        // 2. 更新学者基本信息（如果有）
        if let name = snapshot.scholarName, let citations = snapshot.totalCitations {
            let oldInfo = scholarBasicInfo[snapshot.scholarId]
            let newInfo = ScholarBasicInfo(
                scholarId: snapshot.scholarId,
                name: name,
                citations: citations,
                hIndex: snapshot.hIndex,
                i10Index: snapshot.i10Index,
                lastUpdated: snapshot.timestamp,
                source: snapshot.source
            )
            scholarBasicInfo[snapshot.scholarId] = newInfo
            
            // 发送变化通知
            dataChangePublisher.send(
                .scholarInfoUpdated(
                    scholarId: snapshot.scholarId,
                    oldCitations: oldInfo?.citations,
                    newCitations: citations
                )
            )
            
            // 持久化
            persistData()
            
            print("✅ [UnifiedCache] Updated basic info: \(name), citations: \(citations)")
        }
        
        // 3. 更新论文列表（增量更新：只更新引用数发生变化的论文）
        if !snapshot.publications.isEmpty {
            if scholarPublications[snapshot.scholarId] == nil {
                scholarPublications[snapshot.scholarId] = [:]
            }
            if scholarPublications[snapshot.scholarId]?[snapshot.sortBy] == nil {
                scholarPublications[snapshot.scholarId]?[snapshot.sortBy] = []
            }
            
            // 获取现有论文列表
            let existingPublications = scholarPublications[snapshot.scholarId]?[snapshot.sortBy] ?? []
            
            // 增量合并：只更新引用数发生变化的论文
            let mergeResult = mergePublications(
                existing: existingPublications,
                new: snapshot.publications,
                startIndex: snapshot.startIndex
            )
            
            let mergedPublications = mergeResult.merged
            let updatedCount = mergeResult.updatedCount
            let newCount = mergeResult.newCount
            
            // 增量更新策略：只有在引用数发生变化、新增论文或第一页论文数量变化时才更新
            let existingCount = existingPublications.count
            let mergedCount = mergedPublications.count
            let firstPageCountChanged = (snapshot.startIndex == 0 && existingCount != mergedCount)
            
            if updatedCount > 0 || newCount > 0 || firstPageCountChanged {
                scholarPublications[snapshot.scholarId]?[snapshot.sortBy] = mergedPublications
                
                // 发送变化通知
                dataChangePublisher.send(
                    .publicationsUpdated(
                        scholarId: snapshot.scholarId,
                        sortBy: snapshot.sortBy,
                        count: mergedPublications.count
                    )
                )
                
                // 计算详细变化并发送通知（仅针对 total 排序或第一页）
                if snapshot.sortBy == "total" || snapshot.startIndex == 0 {
                    // 转换为 Snapshot 以便对比
                    let oldSnapshots = existingPublications.map { pub in
                        CitationCacheService.PublicationSnapshot(
                            title: pub.title,
                            clusterId: pub.clusterId,
                            citationCount: pub.citationCount,
                            year: pub.year
                        )
                    }
                    
                    let newSnapshots = mergedPublications.map { pub in
                        CitationCacheService.PublicationSnapshot(
                            title: pub.title,
                            clusterId: pub.clusterId,
                            citationCount: pub.citationCount,
                            year: pub.year
                        )
                    }
                    
                    let changes = CitationCacheService.shared.comparePublications(old: oldSnapshots, new: newSnapshots)
                    if changes.hasChanges {
                        dataChangePublisher.send(.publicationsChanged(scholarId: snapshot.scholarId, changes: changes))
                        print("📢 [UnifiedCache] Broadcasted detailed changes: \(changes.totalNewCitations) new citations")
                    }
                }
                
                if updatedCount > 0 || newCount > 0 {
                    print("✅ [UnifiedCache] Incremental update: \(updatedCount) citations updated, \(newCount) new papers, \(mergedCount) total, sortBy: \(snapshot.sortBy)")
                } else if firstPageCountChanged {
                    print("✅ [UnifiedCache] First page count changed: \(existingCount) → \(mergedCount), sortBy: \(snapshot.sortBy)")
                }
                
                // 持久化
                persistData()
            } else {
                print("ℹ️ [UnifiedCache] No changes detected (citations unchanged, no new papers), skipping cache update (sortBy: \(snapshot.sortBy), startIndex: \(snapshot.startIndex))")
            }
        }
    }
    
    // MARK: - 数据获取方法
    
    /// 最小刷新间隔（1小时内不重复请求同一学者）
    private let minimumRefreshInterval: TimeInterval = 60 * 60

    /// 获取学者基本信息
    public func getScholarBasicInfo(scholarId: String) -> ScholarBasicInfo? {
        guard let info = scholarBasicInfo[scholarId] else {
            return nil
        }

        // 检查缓存是否过期
        if Date().timeIntervalSince(info.lastUpdated) > cacheExpirationInterval {
            print("⚠️ [UnifiedCache] Basic info expired for \(scholarId)")
            return nil
        }

        return info
    }

    /// 检查学者数据是否足够新鲜（在最小刷新间隔内），不需要重新获取
    /// - Returns: true 表示数据仍然新鲜，不需要网络请求
    public func isDataFresh(scholarId: String) -> Bool {
        guard let info = scholarBasicInfo[scholarId] else {
            return false
        }
        return Date().timeIntervalSince(info.lastUpdated) < minimumRefreshInterval
    }
    
    /// 获取论文列表
    public func getPublications(
        scholarId: String,
        sortBy: String,
        startIndex: Int = 0,
        limit: Int = 100
    ) -> [ScholarPublication]? {
        guard let publicationsBySort = scholarPublications[scholarId],
              let publications = publicationsBySort[sortBy] else {
            return nil
        }
        
        // 返回指定范围的论文
        // 使用安全的加法，防止溢出（特别是当 limit 是 Int.max 时）
        let safeLimit = min(limit, Int.max - startIndex)
        let endIndex = min(startIndex + safeLimit, publications.count)
        guard startIndex < publications.count else {
            return []
        }
        
        return Array(publications[startIndex..<endIndex])
    }
    
    /// 检查是否需要获取更多论文
    public func needsFetchMore(
        scholarId: String,
        sortBy: String,
        requestedIndex: Int
    ) -> Bool {
        guard let publicationsBySort = scholarPublications[scholarId],
              let publications = publicationsBySort[sortBy] else {
            return true  // 没有缓存，需要获取
        }
        
        // 如果请求的索引超出当前缓存的范围，需要获取更多
        return requestedIndex >= publications.count
    }
    
    // MARK: - 辅助方法
    
    /// 合并论文列表（增量更新：只更新引用数发生变化的论文）
    /// - Returns: (合并后的论文列表, 更新的论文数量, 新增的论文数量)
    private func mergePublications(
        existing: [ScholarPublication],
        new: [ScholarPublication],
        startIndex: Int
    ) -> (merged: [ScholarPublication], updatedCount: Int, newCount: Int) {
        // 创建现有论文的字典（以 clusterId 为 key，如果没有 clusterId 则用 title+year 组合）
        var existingDict: [String: ScholarPublication] = [:]
        for pub in existing {
            let key = pub.clusterId ?? "\(pub.title)_\(pub.year ?? 0)"
            existingDict[key] = pub
        }
        
        var updatedCount = 0
        var newCount = 0
        var result: [ScholarPublication] = []
        
        // 处理新论文
        for newPub in new {
            let key = newPub.clusterId ?? "\(newPub.title)_\(newPub.year ?? 0)"
            
            if let existingPub = existingDict[key] {
                // 论文已存在，检查引用数是否变化
                let oldCitationCount = existingPub.citationCount ?? 0
                let newCitationCount = newPub.citationCount ?? 0
                
                if oldCitationCount != newCitationCount {
                    // 引用数发生变化，更新论文
                    result.append(newPub)
                    updatedCount += 1
                    print("🔄 [UnifiedCache] Citation count updated: '\(newPub.title.prefix(50))...' \(oldCitationCount) → \(newCitationCount)")
                } else if existingPub.authors.isEmpty && !newPub.authors.isEmpty {
                    // 引用数未变化，但旧数据缺少作者信息 → 用新数据补全
                    result.append(newPub)
                    updatedCount += 1
                } else {
                    // 引用数未变化，保留原有论文（避免不必要的更新）
                    result.append(existingPub)
                }
                // 从字典中移除，表示已处理
                existingDict.removeValue(forKey: key)
            } else {
                // 新论文，直接添加
                result.append(newPub)
                newCount += 1
            }
        }
        
        // 如果是第一页（startIndex == 0），只保留 result 中的论文（第一页的论文）
        // 如果是后续页，保留所有现有论文（包括未在新数据中的）
        if startIndex == 0 {
            // 第一页：只保留 result 中的论文（已更新或新增的第一页论文）
            // 注意：不在第一页的现有论文会被移除，因为它们会在后续页中处理
            // result 已经包含了所有第一页的论文（已更新引用数的 + 未变化的 + 新增的）
        } else {
            // 后续页：保留所有现有论文（包括未在新数据中的）
            for (_, existingPub) in existingDict {
                result.append(existingPub)
            }
        }
        
        return (result, updatedCount, newCount)
    }
    
    /// 清除学者的所有缓存
    public func clearCache(for scholarId: String) {
        scholarBasicInfo.removeValue(forKey: scholarId)
        scholarPublications.removeValue(forKey: scholarId)
        dataSnapshots.removeValue(forKey: scholarId)
        
        // 持久化
        persistData()
        
        print("🗑️ [UnifiedCache] Cleared cache for \(scholarId)")
    }
    
    /// 清除所有缓存
    public func clearAllCache() {
        scholarBasicInfo.removeAll()
        scholarPublications.removeAll()
        citingPapersCache.removeAll()
        dataSnapshots.removeAll()
        
        // 持久化
        persistData()
        
        // 清除持久化数据
        clearPersistedData()
        
        print("🗑️ [UnifiedCache] Cleared all cache")
    }
    
    // MARK: - 调试方法
    
    /// 获取缓存统计信息
    public func getCacheStats() -> CacheStats {
        return CacheStats(
            scholarCount: scholarBasicInfo.count,
            publicationCount: scholarPublications.values.reduce(0) { count, sortDict in
                count + sortDict.values.reduce(0) { $0 + $1.count }
            },
            snapshotCount: dataSnapshots.values.reduce(0) { $0 + $1.count }
        )
    }
    
    public struct CacheStats {
        public let scholarCount: Int
        public let publicationCount: Int
        public let snapshotCount: Int
    }
    
    /// 计算缓存大小（字节）
    public func calculateCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        // 计算内存中数据的大小（近似值）
        // 1. 学者基本信息
        for (_, info) in scholarBasicInfo {
            totalSize += Int64(MemoryLayout.size(ofValue: info.scholarId))
            totalSize += Int64(info.name.utf8.count)
            totalSize += Int64(MemoryLayout<Int>.size) // citations
            if info.hIndex != nil {
                totalSize += Int64(MemoryLayout<Int>.size)
            }
            if info.i10Index != nil {
                totalSize += Int64(MemoryLayout<Int>.size)
            }
        }
        
        // 2. 论文列表
        for (_, sortDict) in scholarPublications {
            for (_, publications) in sortDict {
                for pub in publications {
                    totalSize += Int64(pub.title.utf8.count)
                    totalSize += Int64(pub.id.utf8.count)
                    if let clusterId = pub.clusterId {
                        totalSize += Int64(clusterId.utf8.count)
                    }
                    if pub.citationCount != nil {
                        totalSize += Int64(MemoryLayout<Int>.size)
                    }
                    if pub.year != nil {
                        totalSize += Int64(MemoryLayout<Int>.size)
                    }
                }
            }
        }
        
        // 3. 引用文章缓存
        for (_, sortDict) in citingPapersCache {
            for (_, papers) in sortDict {
                for paper in papers {
                    totalSize += Int64(paper.title.utf8.count)
                    totalSize += Int64(paper.authors.joined(separator: ", ").utf8.count)
                    if let venue = paper.venue {
                        totalSize += Int64(venue.utf8.count)
                    }
                }
            }
        }
        
        // 4. 计算持久化存储的大小
        let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
        if let data = appGroupDefaults.data(forKey: persistenceKey) {
            totalSize += Int64(data.count)
        }
        
        return totalSize
    }
    
    /// 格式化缓存大小为可读字符串
    public func getFormattedCacheSize() -> String {
        let size = calculateCacheSize()
        return formatBytes(size)
    }
    
    /// 格式化字节数为可读字符串
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

