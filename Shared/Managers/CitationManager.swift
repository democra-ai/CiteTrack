import Foundation
import Combine

// MARK: - Citation Manager
@MainActor
public class CitationManager: ObservableObject {
    public static let shared = CitationManager()
    
    // Published properties
    @Published public var citingPapers: [String: [CitingPaper]] = [:]  // scholarId -> papers
    @Published public var citingAuthors: [String: [CitingAuthor]] = [:]  // scholarId -> authors
    @Published public var statistics: [String: CitationStatistics] = [:]  // scholarId -> stats
    @Published public var scholarPublications: [String: [PublicationInfo]] = [:]  // scholarId -> publications
    @Published public var publicationChanges: [String: CitationCacheService.PublicationChanges] = [:]  // scholarId -> changes
    @Published public var isLoading: Bool = false
    @Published public var isLoadingMore: Bool = false  // 加载更多时的状态
    @Published public var hasMorePublications: [String: Bool] = [:]  // scholarId -> 是否还有更多论文
    @Published public var error: CitationFetchService.CitationError?
    
    // Services
    private let fetchService: CitationFetchService
    private let cacheService: CitationCacheService
    private let exportService: CitationExportService
    
    // 新增：获取协调器（延迟初始化，确保在主线程上访问）
    public let fetchCoordinator: CitationFetchCoordinator
    
    // Cancellables
    private var cancellables = Set<AnyCancellable>()
    private var cacheSubscription: AnyCancellable?
    
    private init() {
        self.fetchService = CitationFetchService.shared
        self.cacheService = CitationCacheService.shared
        self.exportService = CitationExportService.shared
        self.fetchCoordinator = CitationFetchCoordinator.shared
        
        // 订阅统一缓存的数据变化事件
        setupCacheSubscription()
    }
    
    // MARK: - Cache Subscription
    
    /// 设置统一缓存的订阅
    private func setupCacheSubscription() {
        Task { @MainActor in
            cacheSubscription = UnifiedCacheManager.shared.dataChangePublisher
                .sink { [weak self] change in
                    self?.handleCacheChange(change)
                }
            print("📢 [CitationManager] Subscribed to unified cache changes")
        }
    }
    
    /// 处理缓存变化事件
    private func handleCacheChange(_ change: UnifiedCacheManager.DataChangeEvent) {
        Task { @MainActor in
            switch change {
            case .scholarInfoUpdated(let scholarId, let oldCitations, let newCitations):
                print("📢 [CitationManager] Scholar \(scholarId) citations updated: \(oldCitations ?? 0) -> \(newCitations ?? 0)")
                // 通知 UI 刷新（如果正在显示这个学者的数据）
                
            case .publicationsUpdated(let scholarId, let sortBy, let count):
                print("📢 [CitationManager] Publications updated for \(scholarId), sortBy: \(sortBy), count: \(count)")
                // 如果当前正在显示这个学者的论文列表，自动刷新
                
            case .newPublicationsDetected(let scholarId, let newCount):
                print("📢 [CitationManager] New publications detected for \(scholarId): \(newCount)")
                
            case .publicationsChanged(let scholarId, let changes):
                print("📢 [CitationManager] Detailed changes received for \(scholarId): \(changes.totalNewCitations) new citations")
                self.publicationChanges[scholarId] = changes
                
            case .citingPapersUpdated(let clusterId, let count):
                print("📢 [CitationManager] Citing papers updated for cluster \(clusterId): \(count)")
            }
        }
    }
    
    // MARK: - Fetch Citing Papers
    
    /// 获取学者的论文列表（使用新的批量预取策略）
    public func fetchScholarPublications(for scholarId: String, sortBy: String? = nil, forceRefresh: Bool = false) {
        Task { @MainActor in
            await fetchScholarPublicationsAsync(for: scholarId, sortBy: sortBy, forceRefresh: forceRefresh)
        }
    }
    
    /// 异步获取学者的论文列表
    public func fetchScholarPublicationsAsync(for scholarId: String, sortBy: String? = nil, forceRefresh: Bool = false) async {
        logInfo("Fetching scholar publications for: \(scholarId), sortBy: \(sortBy ?? "default"), forceRefresh: \(forceRefresh)")
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        // 计算起始索引
        // 如果是强制刷新，从 0 开始
        // 否则，检查当前学者是否有数据：
        //   - 如果没有数据，从 0 开始（首次加载或切换学者）
        //   - 如果有数据，使用已有数据的数量（用于加载更多）
        let currentCount = await MainActor.run {
            scholarPublications[scholarId]?.count ?? 0
        }
        // 如果当前没有数据，总是从 0 开始（切换学者时的情况）
        // 如果有数据，使用已有数据的数量（用于加载更多）
        let startIndex = forceRefresh ? 0 : (currentCount == 0 ? 0 : currentCount)
        
        // 如果当前没有数据，确保清空可能存在的旧数据
        // 注意：不清空统计数据，避免在数据加载过程中显示错误的引用数
        if currentCount == 0 {
            await MainActor.run {
                // 清空该学者的论文列表，确保从第一页开始加载
                // 但不清空统计数据，保留之前的引用数显示，直到新数据加载完成
                scholarPublications[scholarId] = []
                hasMorePublications[scholarId] = true
            }
        }
        let effectiveSortBy = sortBy ?? "total"
        
        // 1. 优先检查统一缓存（UnifiedCacheManager）
        if !forceRefresh {
            // 如果当前没有数据，总是从 startIndex: 0 开始检查缓存
            // 如果有数据，检查对应 startIndex 的缓存（用于加载更多）
            let cacheStartIndex = startIndex
            // 首次加载时只显示20篇论文（Google Scholar默认显示的数量），加载更多时才显示更多
            let limit = (cacheStartIndex == 0) ? 20 : 100
            // 同步检查统一缓存（UnifiedCacheManager 是 @MainActor，已经在主线程）
            let unifiedPublications = await MainActor.run {
                UnifiedCacheManager.shared.getPublications(scholarId: scholarId, sortBy: effectiveSortBy, startIndex: cacheStartIndex, limit: limit)
            }
            
            if let unifiedPublications = unifiedPublications, !unifiedPublications.isEmpty {
                logInfo("💾 [UnifiedCache] Using cached publications for: \(scholarId), sortBy: \(effectiveSortBy), startIndex: \(cacheStartIndex), count: \(unifiedPublications.count)")
                
                // 转换为 PublicationInfo
                let pubInfos = unifiedPublications.map { pub in
                    PublicationInfo(
                        id: pub.id,
                        title: pub.title,
                        clusterId: pub.clusterId,
                        citationCount: pub.citationCount,
                        year: pub.year
                    )
                }
                
                // 同步到旧缓存（保持兼容性）
                cacheService.cacheScholarPublicationsList(
                    unifiedPublications,
                    for: scholarId,
                    sortBy: effectiveSortBy,
                    startIndex: cacheStartIndex
                )
                
                // 判断是否还有更多论文
                // 检查缓存中是否还有更多数据
                let totalCached = await MainActor.run {
                    UnifiedCacheManager.shared.scholarPublications[scholarId]?[effectiveSortBy]?.count ?? 0
                }
                // 如果缓存总数 > 当前返回的数量，说明还有更多
                let hasMore = totalCached > cacheStartIndex + unifiedPublications.count
                
                await MainActor.run {
                    self.hasMorePublications[scholarId] = hasMore
                    
                    if cacheStartIndex == 0 {
                        // 首次加载：替换数据
                        self.scholarPublications[scholarId] = pubInfos
                    } else {
                        // 加载更多：追加数据
                        var existing = self.scholarPublications[scholarId] ?? []
                        existing.append(contentsOf: pubInfos)
                        self.scholarPublications[scholarId] = existing
                    }
                    
                    self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
                    self.isLoading = false
                }
                
                // 不再自动预取多页数据，只使用缓存，避免不必要的 Fetch
                return
            }
        }
        
        // 2. 检查旧缓存（CitationCacheService）- 向后兼容
        // 使用与统一缓存相同的逻辑
        if !forceRefresh, let cachedPublications = cacheService.getCachedScholarPublicationsList(for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex) {
            // 首次加载时只显示20篇论文，加载更多时才显示更多
            let limitedPublications = (startIndex == 0) ? Array(cachedPublications.prefix(20)) : cachedPublications
            logInfo("💾 [OldCache] Using cached publications for: \(scholarId), sortBy: \(effectiveSortBy), startIndex: \(startIndex), count: \(limitedPublications.count)")
            
            // 转换为 PublicationInfo
            let pubInfos = limitedPublications.map { pub in
                PublicationInfo(
                    id: pub.id,
                    title: pub.title,
                    clusterId: pub.clusterId,
                    citationCount: pub.citationCount,
                    year: pub.year
                )
            }
            
            // 同步到统一缓存（迁移数据）
            Task { @MainActor in
                let snapshot = ScholarDataSnapshot(
                    scholarId: scholarId,
                    timestamp: Date(),
                    scholarName: nil,
                    totalCitations: nil,
                    hIndex: nil,
                    i10Index: nil,
                    publications: cachedPublications,
                    sortBy: effectiveSortBy,
                    startIndex: startIndex,
                    source: .whoCiteMe
                )
                UnifiedCacheManager.shared.saveDataSnapshot(snapshot)
                print("📦 [CitationManager] Migrated old cache to unified cache")
            }
            
            // 判断是否还有更多论文
            // 检查原始缓存中是否还有更多数据
            let hasMore = cachedPublications.count > limitedPublications.count || (startIndex == 0 && cachedPublications.count > 20)
            
            await MainActor.run {
                self.hasMorePublications[scholarId] = hasMore
                
                if startIndex == 0 {
                    // 首次加载：替换数据
                    self.scholarPublications[scholarId] = pubInfos
                } else {
                    // 加载更多：追加数据
                    var existing = self.scholarPublications[scholarId] ?? []
                    existing.append(contentsOf: pubInfos)
                    self.scholarPublications[scholarId] = existing
                }
                
                self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
                self.isLoading = false
            }
            
            // 不再自动预取多页数据，只使用缓存，避免不必要的 Fetch
            return
        }
        
        // 缓存未命中或强制刷新，只获取第一页，不预取多页
        if forceRefresh {
            logInfo("🔄 Force refresh: fetching first page for: \(scholarId), sortBy: \(effectiveSortBy), startIndex: 0")
            // 强制刷新时清空现有显示，显示加载状态，然后显示新数据
            await MainActor.run {
                scholarPublications[scholarId] = []
                hasMorePublications[scholarId] = true
            }
        } else {
            logInfo("🚀 Cache miss, fetching first page only for: \(scholarId), sortBy: \(effectiveSortBy), startIndex: 0")
        }
        
        Task { @MainActor in
            // 强制刷新时：清空当前显示，显示加载状态，直接 Fetch
            if forceRefresh {
                // 清空当前显示，显示加载状态
                self.scholarPublications[scholarId] = []
                self.hasMorePublications[scholarId] = true
                self.isLoading = true
                
                // 直接 Fetch，跳过缓存检查
                await fetchCoordinator.fetchScholarProfilePage(
                    scholarId: scholarId,
                    sortBy: effectiveSortBy,
                    startIndex: 0,
                    priority: .high
                )
            } else {
                // 非强制刷新：优先检查对应排序的缓存
                // 检查是否有对应 sortBy 的缓存数据
                let hasCachedData = UnifiedCacheManager.shared.getPublications(scholarId: scholarId, sortBy: effectiveSortBy, startIndex: 0, limit: 20) != nil
                
                if hasCachedData {
                    // 有对应排序的缓存：立即显示缓存，后台静默更新
                    if let unifiedPublications = UnifiedCacheManager.shared.getPublications(scholarId: scholarId, sortBy: effectiveSortBy, startIndex: 0, limit: 20) {
                        let pubInfos = unifiedPublications.map { pub in
                            PublicationInfo(
                                id: pub.id,
                                title: pub.title,
                                clusterId: pub.clusterId,
                                citationCount: pub.citationCount,
                                year: pub.year
                            )
                        }
                        
                        let totalCached = UnifiedCacheManager.shared.scholarPublications[scholarId]?[effectiveSortBy]?.count ?? 0
                        // 如果缓存中的数量大于当前显示的数量，或者缓存数量达到20（一页的数量），则认为还有更多
                        // 这样可以确保即使缓存耗尽，用户也能触发网络请求加载更多
                        let hasMore = totalCached > unifiedPublications.count || totalCached >= 20
                        
                        self.hasMorePublications[scholarId] = hasMore
                        self.scholarPublications[scholarId] = pubInfos
                        self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
                        self.isLoading = false
                        
                        // 后台静默更新（不阻塞UI）
                        Task {
                            await fetchCoordinator.fetchScholarProfilePage(
                                scholarId: scholarId,
                                sortBy: effectiveSortBy,
                                startIndex: 0,
                                priority: .medium
                            )
                        }
                        return
                    }
                }
                
                // 没有对应排序的缓存：清空当前显示，立即 Fetch（切换排序时需要显示加载状态）
                // 清空当前显示，避免显示错误排序的数据
                // 注意：这里已经在 MainActor 上下文中，可以直接更新
                self.scholarPublications[scholarId] = []
                self.hasMorePublications[scholarId] = true
                self.isLoading = true  // 显示加载状态
                
                // 立即 Fetch 对应排序的数据
                await fetchCoordinator.fetchScholarProfilePage(
                    scholarId: scholarId,
                    sortBy: effectiveSortBy,
                    startIndex: 0,
                    priority: .high
                )
            }
            
            // 第一页完成后，从缓存加载数据到UI（只显示第一页，20篇）
            // 优先从 UnifiedCacheManager 获取（只获取第一页）
            if let unifiedPublications = UnifiedCacheManager.shared.getPublications(scholarId: scholarId, sortBy: effectiveSortBy, startIndex: 0, limit: 20) {
                logInfo("✅ Loaded \(unifiedPublications.count) publications from UnifiedCache after first page fetch")
                
                let pubInfos = unifiedPublications.map { pub in
                    PublicationInfo(
                        id: pub.id,
                        title: pub.title,
                        clusterId: pub.clusterId,
                        citationCount: pub.citationCount,
                        year: pub.year
                    )
                }
                
                // 判断是否还有更多论文（检查缓存中是否还有更多数据）
                let totalCached = UnifiedCacheManager.shared.scholarPublications[scholarId]?[effectiveSortBy]?.count ?? 0
                // 如果缓存总数 > 20，或者返回了100篇（说明还有更多），则允许加载更多
                let hasMore = totalCached > 20 || unifiedPublications.count >= 100
                self.hasMorePublications[scholarId] = hasMore
                
                // 只显示第一页（20篇）
                self.scholarPublications[scholarId] = pubInfos
                
                self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
            } else if let cachedPublications = cacheService.getCachedScholarPublicationsList(for: scholarId, sortBy: effectiveSortBy, startIndex: 0) {
                // 后备：从旧缓存获取（只显示前20篇）
                let limitedPublications = Array(cachedPublications.prefix(20))
                logInfo("✅ Loaded \(limitedPublications.count) publications from old cache after first page fetch")
                
                let pubInfos = limitedPublications.map { pub in
                    PublicationInfo(
                        id: pub.id,
                        title: pub.title,
                        clusterId: pub.clusterId,
                        citationCount: pub.citationCount,
                        year: pub.year
                    )
                }
                
                // 判断是否还有更多论文
                let hasMore = cachedPublications.count > 20 || cachedPublications.count >= 100
                self.hasMorePublications[scholarId] = hasMore
                
                // 只显示第一页（20篇）
                self.scholarPublications[scholarId] = pubInfos
                
                self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
            } else {
                logInfo("⚠️ No cached publications found after first page fetch for: \(scholarId), sortBy: \(effectiveSortBy), startIndex: 0")
            }
            
            self.isLoading = false
        }
    }
    
    /// 旧的获取方法（保留作为后备）
    private func fetchScholarPublicationsLegacy(for scholarId: String, sortBy: String? = nil, forceRefresh: Bool = false) {
        let startIndex = 0
        fetchService.fetchScholarPublications(for: scholarId, sortBy: sortBy, startIndex: startIndex, forceRefresh: forceRefresh) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let publications):
                    self.logSuccess("Fetched \(publications.count) publications starting from index \(startIndex)")
                    
                    // 转换为 PublicationInfo
                    let pubInfos = publications.map { pub in
                        PublicationInfo(
                            id: pub.id,
                            title: pub.title,
                            clusterId: pub.clusterId,
                            citationCount: pub.citationCount,
                            year: pub.year
                        )
                    }
                    
                    // 转换为 PublicationSnapshot 用于缓存和对比
                    let snapshots = publications.map { pub in
                        CitationCacheService.PublicationSnapshot(
                            title: pub.title,
                            clusterId: pub.clusterId,
                            citationCount: pub.citationCount,
                            year: pub.year
                        )
                    }
                    
                    // 判断是否还有更多论文（如果返回的论文数少于100，说明没有更多了）
                    let hasMore = publications.count >= 100
                    self.hasMorePublications[scholarId] = hasMore
                    
                    // 缓存分页数据
                    self.cacheService.cacheScholarPublicationsList(publications, for: scholarId, sortBy: sortBy, startIndex: startIndex)
                    
                    if forceRefresh || startIndex == 0 {
                        // 首次加载或强制刷新：替换数据
                        // 对比变化（只在首次加载时对比）
                        if let cachedPublications = self.cacheService.getCachedPublications(for: scholarId) {
                            let changes = self.cacheService.comparePublications(old: cachedPublications, new: snapshots)
                            if changes.hasChanges {
                                self.logSuccess("Found \(changes.totalNewCitations) new citations across \(changes.increased.count) publications")
                                self.publicationChanges[scholarId] = changes
                            }
                        }
                        
                        // 缓存新数据（用于变化对比）
                        self.cacheService.cachePublications(snapshots, for: scholarId)
                        
                        self.scholarPublications[scholarId] = pubInfos
                    } else {
                        // 加载更多：追加数据
                        var existing = self.scholarPublications[scholarId] ?? []
                        existing.append(contentsOf: pubInfos)
                        self.scholarPublications[scholarId] = existing
                    }
                    
                    self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
                    
                case .failure(let error):
                    self.logError("Failed to fetch publications", error: error)
                    self.error = error
                    // 如果加载失败，假设没有更多了
                    self.hasMorePublications[scholarId] = false
                }
            }
        }
    }
    
    /// 加载更多论文（分页加载）
    public func loadMorePublications(for scholarId: String, sortBy: String? = nil) {
        // 如果正在加载或没有更多，则不加载
        guard !isLoadingMore,
              hasMorePublications[scholarId] != false else {
            return
        }
        
        logInfo("Loading more publications for: \(scholarId)")
        isLoadingMore = true
        
        let startIndex = scholarPublications[scholarId]?.count ?? 0
        let effectiveSortBy = sortBy ?? "total"
        
        // 1. 优先检查统一缓存（UnifiedCacheManager）
        Task { @MainActor in
            // 加载更多时，每次加载100篇（Google Scholar 每页100篇）
            let limit = 100
            let unifiedPublications = UnifiedCacheManager.shared.getPublications(
                scholarId: scholarId,
                sortBy: effectiveSortBy,
                startIndex: startIndex,
                limit: limit
            )
            
            if let unifiedPublications = unifiedPublications, !unifiedPublications.isEmpty {
                logInfo("💾 [UnifiedCache] Using cached publications for load more: \(scholarId), sortBy: \(effectiveSortBy), startIndex: \(startIndex), count: \(unifiedPublications.count)")
                
                // 转换为 PublicationInfo
                let pubInfos = unifiedPublications.map { pub in
                    PublicationInfo(
                        id: pub.id,
                        title: pub.title,
                        clusterId: pub.clusterId,
                        citationCount: pub.citationCount,
                        year: pub.year
                    )
                }
                
                // 判断是否还有更多论文
                // 如果返回了100篇，说明可能还有更多；或者检查缓存总数
                let totalCached = UnifiedCacheManager.shared.scholarPublications[scholarId]?[effectiveSortBy]?.count ?? 0
                let hasMore = unifiedPublications.count >= 100 || totalCached > startIndex + unifiedPublications.count
                self.hasMorePublications[scholarId] = hasMore
                
                // 同步到旧缓存（保持兼容性）
                self.cacheService.cacheScholarPublicationsList(
                    unifiedPublications,
                    for: scholarId,
                    sortBy: effectiveSortBy,
                    startIndex: startIndex
                )
                
                // 追加数据
                var existing = self.scholarPublications[scholarId] ?? []
                existing.append(contentsOf: pubInfos)
                self.scholarPublications[scholarId] = existing
                
                self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
                self.isLoadingMore = false
                
                // 在后台更新数据（静默刷新）
                Task.detached(priority: .utility) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        self.fetchService.fetchScholarPublications(for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex, forceRefresh: false) { result in
                            // 静默更新缓存
                            if case .success(let publications) = result {
                                Task { @MainActor in
                                    self.cacheService.cacheScholarPublicationsList(publications, for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex)
                                    // 同时更新统一缓存
                                    let snapshot = ScholarDataSnapshot(
                                        scholarId: scholarId,
                                        timestamp: Date(),
                                        scholarName: nil,
                                        totalCitations: nil,
                                        hIndex: nil,
                                        i10Index: nil,
                                        publications: publications,
                                        sortBy: effectiveSortBy,
                                        startIndex: startIndex,
                                        source: .whoCiteMe
                                    )
                                    UnifiedCacheManager.shared.saveDataSnapshot(snapshot)
                                    continuation.resume()
                                }
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                }
                return
            }
            
            // 2. 检查旧缓存（CitationCacheService）- 向后兼容
            if let cachedPublications = self.cacheService.getCachedScholarPublicationsList(for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex) {
                logInfo("💾 [OldCache] Using cached publications for load more: \(scholarId), sortBy: \(effectiveSortBy), startIndex: \(startIndex)")
                
                // 转换为 PublicationInfo
                let pubInfos = cachedPublications.map { pub in
                    PublicationInfo(
                        id: pub.id,
                        title: pub.title,
                        clusterId: pub.clusterId,
                        citationCount: pub.citationCount,
                        year: pub.year
                    )
                }
                
                // 判断是否还有更多论文
                // 1. 如果返回的数据量 >= 100，肯定还有更多
                // 2. 如果返回的数据量 < 100，可能只是缓存不完整，允许尝试加载更多
                let hasMore = cachedPublications.count >= 100 || cachedPublications.count < 100
                self.hasMorePublications[scholarId] = hasMore
                
                // 同步到统一缓存（迁移数据）
                let snapshot = ScholarDataSnapshot(
                    scholarId: scholarId,
                    timestamp: Date(),
                    scholarName: nil,
                    totalCitations: nil,
                    hIndex: nil,
                    i10Index: nil,
                    publications: cachedPublications,
                    sortBy: effectiveSortBy,
                    startIndex: startIndex,
                    source: .whoCiteMe
                )
                UnifiedCacheManager.shared.saveDataSnapshot(snapshot)
                
                // 追加数据
                var existing = self.scholarPublications[scholarId] ?? []
                existing.append(contentsOf: pubInfos)
                self.scholarPublications[scholarId] = existing
                
                self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
                self.isLoadingMore = false
                
                // 在后台更新数据（静默刷新）
                Task.detached(priority: .utility) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        self.fetchService.fetchScholarPublications(for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex, forceRefresh: false) { result in
                            // 静默更新缓存
                            if case .success(let publications) = result {
                                Task { @MainActor in
                                    self.cacheService.cacheScholarPublicationsList(publications, for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex)
                                    // 同时更新统一缓存
                                    let snapshot = ScholarDataSnapshot(
                                        scholarId: scholarId,
                                        timestamp: Date(),
                                        scholarName: nil,
                                        totalCitations: nil,
                                        hIndex: nil,
                                        i10Index: nil,
                                        publications: publications,
                                        sortBy: effectiveSortBy,
                                        startIndex: startIndex,
                                        source: .whoCiteMe
                                    )
                                    UnifiedCacheManager.shared.saveDataSnapshot(snapshot)
                                    continuation.resume()
                                }
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                }
                return
            }
            
            // 3. 缓存未命中，从网络获取
            self.fetchService.fetchScholarPublications(for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex, forceRefresh: false) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoadingMore = false
                    
                    switch result {
                    case .success(let publications):
                        // 缓存分页数据
                        self.cacheService.cacheScholarPublicationsList(publications, for: scholarId, sortBy: effectiveSortBy, startIndex: startIndex)
                        
                        // 同时更新统一缓存
                        Task { @MainActor in
                            let snapshot = ScholarDataSnapshot(
                                scholarId: scholarId,
                                timestamp: Date(),
                                scholarName: nil,
                                totalCitations: nil,
                                hIndex: nil,
                                i10Index: nil,
                                publications: publications,
                                sortBy: effectiveSortBy,
                                startIndex: startIndex,
                                source: .whoCiteMe
                            )
                            UnifiedCacheManager.shared.saveDataSnapshot(snapshot)
                        }
                        
                        // 转换为 PublicationInfo
                        let pubInfos = publications.map { pub in
                            PublicationInfo(
                                id: pub.id,
                                title: pub.title,
                                clusterId: pub.clusterId,
                                citationCount: pub.citationCount,
                                year: pub.year
                            )
                        }
                        
                        // 判断是否还有更多论文
                        let hasMore = publications.count >= 100
                        self.hasMorePublications[scholarId] = hasMore
                        
                        // 追加数据
                        var existing = self.scholarPublications[scholarId] ?? []
                        existing.append(contentsOf: pubInfos)
                        self.scholarPublications[scholarId] = existing
                        
                        self.updatePublicationStatistics(for: scholarId, publications: self.scholarPublications[scholarId] ?? [])
                        
                    case .failure(let error):
                        self.logError("Failed to load more publications", error: error)
                        self.error = error
                        self.hasMorePublications[scholarId] = false
                    }
                }
            }
        }
    }
    
    /// 获取引用论文（优先使用缓存）- 已弃用，改用fetchScholarPublications
    @available(*, deprecated, message: "Use fetchScholarPublications instead due to Google Scholar restrictions")
    public func fetchCitingPapers(for scholarId: String, forceRefresh: Bool = false) {
        logInfo("fetchCitingPapers is deprecated, using fetchScholarPublications instead")
        fetchScholarPublications(for: scholarId, forceRefresh: forceRefresh)
    }
    
    // MARK: - Fetch Citing Authors
    
    /// 获取引用作者
    public func fetchCitingAuthors(for scholarId: String, forceRefresh: Bool = false) {
        logInfo("Fetching citing authors for scholar: \(scholarId)")
        
        // 如果不强制刷新且有缓存，使用缓存
        if !forceRefresh {
            if let cachedAuthors = cacheService.getCachedCitingAuthors(for: scholarId) {
                logInfo("Using cached authors (\(cachedAuthors.count) authors)")
                DispatchQueue.main.async {
                    self.citingAuthors[scholarId] = cachedAuthors
                }
                return
            }
        }
        
        // 从网络获取
        isLoading = true
        error = nil
        
        fetchService.fetchCitingAuthors(for: scholarId) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let authors):
                    self.logSuccess("Fetched \(authors.count) citing authors")
                    self.citingAuthors[scholarId] = authors
                    
                    // 缓存数据
                    self.cacheService.cacheCitingAuthors(authors, for: scholarId)
                    
                case .failure(let error):
                    self.logError("Failed to fetch citing authors", error: error)
                    self.error = error
                    
                    // 尝试使用缓存数据
                    if let cachedAuthors = self.cacheService.getCachedCitingAuthors(for: scholarId) {
                        self.logInfo("Using cached authors as fallback")
                        self.citingAuthors[scholarId] = cachedAuthors
                    }
                }
            }
        }
    }
    
    // MARK: - Statistics
    
    /// 计算引用统计
    public func calculateStatistics(for scholarId: String) -> CitationStatistics {
        let papers = citingPapers[scholarId] ?? []
        let authors = citingAuthors[scholarId] ?? []
        
        // 按年份统计引用数
        var citationsByYear: [Int: Int] = [:]
        for paper in papers {
            if let year = paper.year {
                citationsByYear[year, default: 0] += 1
            }
        }
        
        // 获取最频繁引用的作者（前10位）
        let topAuthors = Array(authors.prefix(10))
        
        // 获取最近的引用（按年份排序，取前10篇）
        let recentCitations = papers
            .sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            .prefix(10)
            .map { $0 }
        
        // 计算年均引用数
        let years = citationsByYear.keys.sorted()
        let averageCitationsPerYear: Double
        if years.count > 1, let earliest = years.first, let latest = years.last {
            let yearSpan = latest - earliest + 1
            averageCitationsPerYear = Double(papers.count) / Double(yearSpan)
        } else {
            averageCitationsPerYear = Double(papers.count)
        }
        
        let stats = CitationStatistics(
            scholarId: scholarId,
            totalCitingPapers: papers.count,
            uniqueCitingAuthors: authors.count,
            citationsByYear: citationsByYear,
            topCitingAuthors: topAuthors,
            recentCitations: Array(recentCitations),
            averageCitationsPerYear: averageCitationsPerYear,
            lastUpdated: Date()
        )
        
        DispatchQueue.main.async {
            self.statistics[scholarId] = stats
        }
        
        return stats
    }
    
    /// 更新统计数据
    private func updateStatistics(for scholarId: String) {
        _ = calculateStatistics(for: scholarId)
    }
    
    /// 更新统计数据 - 直接从 UnifiedCacheManager 获取，不做任何计算
    private func updatePublicationStatistics(for scholarId: String, publications: [PublicationInfo]) {
        // 直接从 UnifiedCacheManager 获取引用数，完全显示，不做任何统计计算
        Task { @MainActor in
            if let basicInfo = UnifiedCacheManager.shared.getScholarBasicInfo(scholarId: scholarId) {
                // 直接使用 UnifiedCacheManager 中的完整引用数（从 Google Scholar 主页获取的准确值）
                let stats = CitationStatistics(
                    scholarId: scholarId,
                    totalCitingPapers: basicInfo.citations,
                    uniqueCitingAuthors: 0,
                    citationsByYear: [:],
                    topCitingAuthors: [],
                    recentCitations: [],
                    averageCitationsPerYear: Double(basicInfo.citations),
                    lastUpdated: basicInfo.lastUpdated
                )
                self.statistics[scholarId] = stats
                logInfo("Updated statistics from UnifiedCache: \(basicInfo.citations) citations for \(scholarId)")
            } else {
                // 如果 UnifiedCacheManager 没有数据，保留之前的统计数据（不清零）
                logInfo("No UnifiedCache data for \(scholarId), preserving previous stats")
            }
        }
    }
}

// MARK: - Publication Info (for iOS views)
public struct PublicationInfo: Identifiable, Codable {
    public let id: String
    public let title: String
    public let clusterId: String?
    public let citationCount: Int?
    public let year: Int?
    
    public init(id: String, title: String, clusterId: String?, citationCount: Int?, year: Int?) {
        self.id = id
        self.title = title
        self.clusterId = clusterId
        self.citationCount = citationCount
        self.year = year
    }
}

extension CitationManager {
    // MARK: - Filter
    
    /// 应用筛选
    public func applyFilter(_ filter: CitationFilter, to papers: [CitingPaper]) -> [CitingPaper] {
        return filter.apply(to: papers)
    }
    
    /// 获取筛选后的论文
    public func getFilteredPapers(for scholarId: String, filter: CitationFilter) -> [CitingPaper] {
        let papers = citingPapers[scholarId] ?? []
        return applyFilter(filter, to: papers)
    }
    
    // MARK: - Export
    
    /// 导出数据
    public func exportData(papers: [CitingPaper], format: CitationExportService.ExportFormat) -> Data? {
        switch format {
        case .csv:
            return exportService.exportToCSV(papers: papers)
        case .json:
            return exportService.exportToJSON(papers: papers)
        case .bibtex:
            return exportService.exportToBibTeX(papers: papers)
        }
    }
    
    /// 导出数据并生成文件名
    public func exportData(
        for scholarId: String,
        papers: [CitingPaper],
        format: CitationExportService.ExportFormat
    ) -> ExportResult? {
        guard let data = exportData(papers: papers, format: format) else {
            return nil
        }
        
        let fileName = exportService.generateFileName(
            for: scholarId,
            format: format,
            paperCount: papers.count
        )
        
        return ExportResult(data: data, fileName: fileName, format: format)
    }
    
    // MARK: - Cache Management
    
    /// 清除缓存
    public func clearCache(for scholarId: String) {
        cacheService.clearCache(for: scholarId)
        
        DispatchQueue.main.async {
            self.citingPapers.removeValue(forKey: scholarId)
            self.citingAuthors.removeValue(forKey: scholarId)
            self.statistics.removeValue(forKey: scholarId)
        }
        
        logInfo("Cleared cache for scholar: \(scholarId)")
    }
    
    /// 清除所有缓存
    public func clearAllCache() {
        cacheService.clearAllCache()
        
        DispatchQueue.main.async {
            self.citingPapers.removeAll()
            self.citingAuthors.removeAll()
            self.statistics.removeAll()
        }
        
        logInfo("Cleared all cache")
    }
    
    /// 获取缓存统计
    public func getCacheStatistics() -> (scholars: Int, papers: Int, authors: Int) {
        return cacheService.getCacheStatistics()
    }
    
    /// 检查缓存是否过期
    public func isCacheExpired(for scholarId: String) -> Bool {
        return cacheService.isCacheExpired(for: scholarId)
    }
    
    /// 获取缓存最后更新时间
    public func getCacheLastUpdated(for scholarId: String) -> Date? {
        return cacheService.getCacheLastUpdated(for: scholarId)
    }
    
    // MARK: - Refresh All Data
    
    /// 刷新所有数据
    public func refreshAllData(for scholarId: String) {
        logInfo("Refreshing all data for scholar: \(scholarId)")
        
        // 清除缓存
        clearCache(for: scholarId)
        
        // 重新获取论文列表（使用新方法）
        fetchScholarPublications(for: scholarId, forceRefresh: true)
    }
    
    // MARK: - Helper Methods
    
    /// 获取论文数量
    public func getPaperCount(for scholarId: String) -> Int {
        return citingPapers[scholarId]?.count ?? 0
    }
    
    /// 获取作者数量
    public func getAuthorCount(for scholarId: String) -> Int {
        return citingAuthors[scholarId]?.count ?? 0
    }
    
    /// 检查是否有数据
    public func hasData(for scholarId: String) -> Bool {
        return getPaperCount(for: scholarId) > 0
    }
    
    /// 检查是否正在加载
    public func isLoadingData(for scholarId: String) -> Bool {
        return isLoading
    }
    
    // MARK: - Logging
    
    private func logInfo(_ message: String) {
        print("ℹ️ [CitationManager] \(message)")
    }
    
    private func logSuccess(_ message: String) {
        print("✅ [CitationManager] \(message)")
    }
    
    private func logWarning(_ message: String) {
        print("⚠️ [CitationManager] \(message)")
    }
    
    private func logError(_ message: String, error: Error? = nil) {
        if let error = error {
            print("❌ [CitationManager] \(message): \(error.localizedDescription)")
        } else {
            print("❌ [CitationManager] \(message)")
        }
    }
}

// MARK: - Combine Extensions
public extension CitationManager {
    /// 使用Combine获取引用论文（已弃用，使用fetchScholarPublicationsPublisher）
    @available(*, deprecated, message: "Use fetchScholarPublicationsPublisher instead")
    func fetchCitingPapersPublisher(for scholarId: String, forceRefresh: Bool = false) -> AnyPublisher<[CitingPaper], Never> {
        return Future { promise in
            // 使用新的方法获取论文
            self.fetchScholarPublications(for: scholarId, forceRefresh: forceRefresh)
            
            // 等待数据更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 返回空数组，因为新方法不填充citingPapers
                promise(.success([]))
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// 使用Combine获取引用作者
    func fetchCitingAuthorsPublisher(for scholarId: String, forceRefresh: Bool = false) -> AnyPublisher<[CitingAuthor], Never> {
        return Future { promise in
            self.fetchCitingAuthors(for: scholarId, forceRefresh: forceRefresh)
            
            // 等待数据更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let authors = self.citingAuthors[scholarId] ?? []
                promise(.success(authors))
            }
        }
        .eraseToAnyPublisher()
    }
}
