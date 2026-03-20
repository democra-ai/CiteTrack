import Foundation

// MARK: - Simple In-Memory Citation Cache Service
// 这是一个简化的内存缓存实现，替代CoreData缓存

public class CitationCacheService {
    public static let shared = CitationCacheService()
    
    // 缓存过期时间（7天 — 与 UnifiedCacheManager 一致，减少 Google Scholar 请求）
    private let cacheExpirationInterval: TimeInterval = 7 * 24 * 60 * 60
    
    // 内存缓存
    private var paperCache: [String: (papers: [CitingPaper], timestamp: Date)] = [:]
    private var authorCache: [String: (authors: [CitingAuthor], timestamp: Date)] = [:]
    private var publicationCache: [String: (publications: [PublicationSnapshot], timestamp: Date)] = [:]
    
    // 引用文章列表缓存（按 clusterId + 排序方式 + 页码）
    // Key: "clusterId_sortByDate_startIndex" (例如: "123456789_true_0")
    private var citingPapersCache: [String: (papers: [CitingPaper], timestamp: Date)] = [:]
    
    // 主论文列表缓存（按 scholarId + 排序方式 + 页码）
    // Key: "scholarId_sortBy_startIndex" (例如: "kukA0LcAAAAJ_total_0")
    private var scholarPublicationsCache: [String: (publications: [ScholarPublication], timestamp: Date)] = [:]
    
    private init() {}
    
    // MARK: - Publication Snapshot (for tracking changes)
    
    public struct PublicationSnapshot: Codable {
        public let title: String
        public let clusterId: String?
        public let citationCount: Int?
        public let year: Int?
        
        public init(title: String, clusterId: String?, citationCount: Int?, year: Int?) {
            self.title = title
            self.clusterId = clusterId
            self.citationCount = citationCount
            self.year = year
        }
    }
    
    // MARK: - Citing Papers Cache
    
    /// 缓存引用论文
    public func cacheCitingPapers(_ papers: [CitingPaper], for scholarId: String) {
        paperCache[scholarId] = (papers, Date())
        logInfo("Cached \(papers.count) papers for scholar: \(scholarId)")
    }
    
    /// 获取缓存的引用论文
    public func getCachedCitingPapers(for scholarId: String) -> [CitingPaper]? {
        guard let cache = paperCache[scholarId] else {
            return nil
        }
        
        // 检查缓存是否过期
        if isCacheExpired(for: scholarId) {
            paperCache.removeValue(forKey: scholarId)
            return nil
        }
        
        return cache.papers
    }
    
    // MARK: - Citing Authors Cache
    
    /// 缓存引用作者
    public func cacheCitingAuthors(_ authors: [CitingAuthor], for scholarId: String) {
        authorCache[scholarId] = (authors, Date())
        logInfo("Cached \(authors.count) authors for scholar: \(scholarId)")
    }
    
    /// 获取缓存的引用作者
    public func getCachedCitingAuthors(for scholarId: String) -> [CitingAuthor]? {
        guard let cache = authorCache[scholarId] else {
            return nil
        }
        
        // 检查缓存是否过期
        if Date().timeIntervalSince(cache.timestamp) > cacheExpirationInterval {
            authorCache.removeValue(forKey: scholarId)
            return nil
        }
        
        return cache.authors
    }
    
    // MARK: - Cache Management
    
    /// 检查缓存是否过期
    public func isCacheExpired(for scholarId: String) -> Bool {
        guard let cache = paperCache[scholarId] else {
            return true
        }
        
        return Date().timeIntervalSince(cache.timestamp) > cacheExpirationInterval
    }
    
    // MARK: - Publications Cache
    
    /// 缓存论文列表
    public func cachePublications(_ publications: [PublicationSnapshot], for scholarId: String) {
        publicationCache[scholarId] = (publications, Date())
        logInfo("Cached \(publications.count) publications for scholar: \(scholarId)")
    }
    
    /// 获取缓存的论文列表
    /// Returns nil if cache is missing or older than 24 hours (forces refresh for comparison)
    public func getCachedPublications(for scholarId: String) -> [PublicationSnapshot]? {
        guard let cache = publicationCache[scholarId] else {
            return nil
        }

        // Publication cache expires after 24 hours to prevent serving stale data indefinitely
        let publicationCacheTTL: TimeInterval = 24 * 60 * 60
        if Date().timeIntervalSince(cache.timestamp) > publicationCacheTTL {
            logInfo("Publication cache expired for scholar: \(scholarId)")
            publicationCache.removeValue(forKey: scholarId)
            return nil
        }

        return cache.publications
    }
    
    /// 对比论文变化
    public func comparePublications(
        old: [PublicationSnapshot],
        new: [PublicationSnapshot]
    ) -> PublicationChanges {
        var increased: [PublicationChange] = []
        var decreased: [PublicationChange] = []
        var newPublications: [PublicationSnapshot] = []
        
        // 创建唯一键的函数：优先使用 clusterId，否则使用 title + year 组合
        func uniqueKey(for pub: PublicationSnapshot) -> String {
            if let clusterId = pub.clusterId, !clusterId.isEmpty {
                return clusterId
            }
            // 使用 title + year 作为后备键
            let year = pub.year.map { String($0) } ?? "unknown"
            return "\(pub.title)_\(year)"
        }
        
        // 创建字典便于查找（使用唯一键）
        let oldDict = Dictionary(uniqueKeysWithValues: old.map { (uniqueKey(for: $0), $0) })
        
        // 检查新论文和引用数变化
        for newPub in new {
            let key = uniqueKey(for: newPub)
            if let oldPub = oldDict[key] {
                // 已存在的论文，检查引用数变化
                let oldCount = oldPub.citationCount ?? 0
                let newCount = newPub.citationCount ?? 0
                let delta = newCount - oldCount
                
                if delta > 0 {
                    increased.append(PublicationChange(
                        publication: newPub,
                        oldCount: oldCount,
                        newCount: newCount,
                        delta: delta
                    ))
                } else if delta < 0 {
                    decreased.append(PublicationChange(
                        publication: newPub,
                        oldCount: oldCount,
                        newCount: newCount,
                        delta: delta
                    ))
                }
            } else {
                // 新增的论文
                newPublications.append(newPub)
            }
        }
        
        return PublicationChanges(
            increased: increased.sorted { $0.delta > $1.delta },
            decreased: decreased,
            newPublications: newPublications
        )
    }
    
    // MARK: - Citing Papers List Cache (for specific publications)
    
    /// 生成引用文章列表的缓存键
    private func citingPapersCacheKey(clusterId: String, sortByDate: Bool, startIndex: Int) -> String {
        return "\(clusterId)_\(sortByDate)_\(startIndex)"
    }
    
    /// 缓存引用文章列表（分页）
    public func cacheCitingPapersList(_ papers: [CitingPaper], for clusterId: String, sortByDate: Bool, startIndex: Int) {
        let key = citingPapersCacheKey(clusterId: clusterId, sortByDate: sortByDate, startIndex: startIndex)
        citingPapersCache[key] = (papers, Date())
        logInfo("Cached \(papers.count) citing papers for cluster: \(clusterId), sortByDate: \(sortByDate), startIndex: \(startIndex)")
    }
    
    /// 获取缓存的引用文章列表
    public func getCachedCitingPapersList(for clusterId: String, sortByDate: Bool, startIndex: Int) -> [CitingPaper]? {
        let key = citingPapersCacheKey(clusterId: clusterId, sortByDate: sortByDate, startIndex: startIndex)
        guard let cache = citingPapersCache[key] else {
            return nil
        }
        
        // 检查缓存是否过期
        if Date().timeIntervalSince(cache.timestamp) > cacheExpirationInterval {
            citingPapersCache.removeValue(forKey: key)
            return nil
        }
        
        return cache.papers
    }
    
    /// 清除特定 clusterId 的所有引用文章缓存
    public func clearCitingPapersCache(for clusterId: String) {
        let keysToRemove = citingPapersCache.keys.filter { $0.hasPrefix("\(clusterId)_") }
        for key in keysToRemove {
            citingPapersCache.removeValue(forKey: key)
        }
        logInfo("Cleared citing papers cache for cluster: \(clusterId)")
    }
    
    // MARK: - Scholar Publications List Cache (for main publication list)
    
    /// 生成主论文列表的缓存键
    private func scholarPublicationsCacheKey(scholarId: String, sortBy: String?, startIndex: Int) -> String {
        let sortKey = sortBy ?? "default"
        return "\(scholarId)_\(sortKey)_\(startIndex)"
    }
    
    /// 缓存主论文列表（分页）
    public func cacheScholarPublicationsList(_ publications: [ScholarPublication], for scholarId: String, sortBy: String?, startIndex: Int) {
        let key = scholarPublicationsCacheKey(scholarId: scholarId, sortBy: sortBy, startIndex: startIndex)
        scholarPublicationsCache[key] = (publications, Date())
        logInfo("Cached \(publications.count) scholar publications for: \(scholarId), sortBy: \(sortBy ?? "default"), startIndex: \(startIndex)")
    }
    
    /// 获取缓存的主论文列表
    public func getCachedScholarPublicationsList(for scholarId: String, sortBy: String?, startIndex: Int) -> [ScholarPublication]? {
        let key = scholarPublicationsCacheKey(scholarId: scholarId, sortBy: sortBy, startIndex: startIndex)
        guard let cache = scholarPublicationsCache[key] else {
            return nil
        }
        
        // 检查缓存是否过期
        if Date().timeIntervalSince(cache.timestamp) > cacheExpirationInterval {
            scholarPublicationsCache.removeValue(forKey: key)
            return nil
        }
        
        return cache.publications
    }
    
    /// 清除特定 scholarId 的所有主论文列表缓存
    public func clearScholarPublicationsCache(for scholarId: String) {
        let keysToRemove = scholarPublicationsCache.keys.filter { $0.hasPrefix("\(scholarId)_") }
        for key in keysToRemove {
            scholarPublicationsCache.removeValue(forKey: key)
        }
        logInfo("Cleared scholar publications cache for: \(scholarId)")
    }
    
    /// 清除特定学者的缓存
    public func clearCache(for scholarId: String) {
        paperCache.removeValue(forKey: scholarId)
        authorCache.removeValue(forKey: scholarId)
        publicationCache.removeValue(forKey: scholarId)
        clearScholarPublicationsCache(for: scholarId)
        logInfo("Cleared cache for scholar: \(scholarId)")
    }
    
    /// 清除所有缓存
    public func clearAllCache() {
        paperCache.removeAll()
        authorCache.removeAll()
        publicationCache.removeAll()
        citingPapersCache.removeAll()
        scholarPublicationsCache.removeAll()
        logInfo("Cleared all cache")
    }
    
    // MARK: - Publication Changes Models
    
    public struct PublicationChange {
        public let publication: PublicationSnapshot
        public let oldCount: Int
        public let newCount: Int
        public let delta: Int
    }
    
    public struct PublicationChanges {
        public let increased: [PublicationChange]
        public let decreased: [PublicationChange]
        public let newPublications: [PublicationSnapshot]
        
        public var hasChanges: Bool {
            return !increased.isEmpty || !decreased.isEmpty || !newPublications.isEmpty
        }
        
        public var totalNewCitations: Int {
            return increased.reduce(0) { $0 + $1.delta }
        }
    }
    
    /// 获取缓存大小信息
    public func getCacheInfo() -> (paperCount: Int, authorCount: Int) {
        return (paperCache.count, authorCache.count)
    }
    
    /// 获取缓存统计（简化版本，返回基本信息）
    public func getCacheStatistics() -> (scholars: Int, papers: Int, authors: Int) {
        return (paperCache.count, paperCache.values.reduce(0) { $0 + $1.papers.count }, authorCache.values.reduce(0) { $0 + $1.authors.count })
    }
    
    /// 获取缓存最后更新时间
    public func getCacheLastUpdated(for scholarId: String) -> Date? {
        return paperCache[scholarId]?.timestamp
    }
}

// MARK: - Logging Helper
private func logInfo(_ message: String) {
    print("[CitationCacheService] \(message)")
}
