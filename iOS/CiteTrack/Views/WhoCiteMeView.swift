import SwiftUI
import Combine

// MARK: - Refresh Trigger
/// 用于触发视图刷新的辅助类
class RefreshTrigger: ObservableObject {
    @Published var value: Int = 0
    
    func trigger() {
        value += 1
    }
}

// MARK: - Publication Display Model
struct PublicationDisplay: Identifiable {
    let id: String
    let title: String
    let clusterId: String?
    let citationCount: Int?
    let year: Int?
}

// MARK: - Publication Display for Sheet (exposed)
struct PublicationDisplayForSheet: Identifiable {
    let id: String
    let title: String
    let clusterId: String?
    let citationCount: Int?
    let year: Int?
    
    init(id: String, title: String, clusterId: String?, citationCount: Int?, year: Int?) {
        self.id = id
        self.title = title
        self.clusterId = clusterId
        self.citationCount = citationCount
        self.year = year
    }
}

// MARK: - Sort Option
enum PublicationSortOption: String, CaseIterable {
    case title = "标题"
    case citations = "引用次数"
    case year = "年份"
    
    var icon: String {
        switch self {
        case .title: return "textformat"
        case .citations: return "quote.bubble"
        case .year: return "calendar"
        }
    }
    
    var title: String {
        switch self {
        case .title: return "sort_by_title".localized
        case .citations: return "sort_by_citations".localized
        case .year: return "sort_by_year".localized
        }
    }
    
    /// 转换为 Google Scholar 的 sortby 参数值
    var googleScholarParam: String? {
        switch self {
        case .title: return "title"
        case .citations: return "total"  // 按引用总数排序
        case .year: return "pubdate"     // 按发表日期排序
        }
    }
}

// MARK: - Badge Count Manager
/// 用于管理导航栏 Badge 数量的可观察对象
class BadgeCountManager: ObservableObject {
    static let shared = BadgeCountManager()
    @Published var count: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 监听 UnifiedCacheManager 的数据变化
        Task { @MainActor in
            UnifiedCacheManager.shared.dataChangePublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.updateCount()
                }
                .store(in: &cancellables)
        }
        
        // 监听 DataManager 的学者列表变化
        Task { @MainActor in
            DataManager.shared.$scholars
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.updateCount()
                }
                .store(in: &cancellables)
        }
        
        // 监听 UserDefaults 变化（已读状态）
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateCount()
            }
            .store(in: &cancellables)
        
        // 初始更新
        updateCount()
    }
    
    func updateCount() {
        let newCount = WhoCiteMeView.getCitedPublicationsCount()
        print("🔔 [BadgeCountManager] Updating count: \(count) -> \(newCount)")
        count = newCount
    }
}

// MARK: - Who Cite Me View
struct WhoCiteMeView: View {
    /// When non-nil, this view is embedded inside the Scholars tab for a specific
    /// scholar. In that mode it skips its own `NavigationView` (the Scholars list
    /// already provides a navigation context) and the horizontal scholar picker,
    /// and pins to this scholar. When nil it behaves as a standalone screen.
    let embeddedScholar: Scholar?

    init(scholar: Scholar? = nil) {
        self.embeddedScholar = scholar
    }

    @StateObject private var citationManager = CitationManager.shared
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var localizationManager = LocalizationManager.shared
    @StateObject private var refreshTrigger = RefreshTrigger()
    
    // 用于访问 BadgeCountManager（不需要 @StateObject，因为 MainView 已经观察了）
    private var badgeCountManager: BadgeCountManager {
        BadgeCountManager.shared
    }
    
    // 用于导航栏 Badge 的共享计数
    static var sharedBadgeCount: Int {
        BadgeCountManager.shared.count
    }
    
    @AppStorage("ConfirmedMyScholarId") private var confirmedMyScholarId: String?
    
    @State private var selectedScholar: Scholar?
    @State private var showingFilterSheet = false
    @State private var showingExportSheet = false
    @State private var currentFilter = CitationFilter()
    @State private var filteredPapers: [CitingPaper] = []
    @State private var selectedPublication: PublicationDisplay?
    @State private var showingCitingPapersSheet = false
    @State private var citingPapers: [CitingPaper] = []
    @State private var isLoadingCitingPapers = false
    @State private var isLoadingMoreCitingPapers = false
    @State private var hasMoreCitingPapers = false
    @State private var citingPapersError: String?
    @State private var citingPapersSortByDate: Bool = true  // 默认按日期排序
    @State private var sortOption: PublicationSortOption = .citations
    @State private var sortAscending: Bool = false  // 注意：Google Scholar 的排序方向由参数决定，这里保留用于UI显示
    @State private var citedPublicationsCount: Int = 0  // 被引用的文章数量
    @State private var showingCitedPublicationsSheet = false  // 显示被引用论文列表的 Sheet
    @State private var citedPublicationsForScholar: [ScholarPublication] = []  // 当前学者的被引用论文列表
    @State private var selectedScholarForBadge: Scholar?  // 点击 Badge 时选择的学者
    
    // 已读状态：存储已查看过的被引用论文的 clusterId（使用 Set 存储）
    @AppStorage("readCitedPublications") private var readCitedPublicationsData: Data = Data()
    
    // 已查看引用列表的论文 clusterId 集合（点击查看引用论文后标记）
    @AppStorage("viewedCitingPapers") private var viewedCitingPapersData: Data = Data()
    
    // 已读论文的 clusterId 集合
    private var readCitedPublicationIds: Set<String> {
        get {
            guard !readCitedPublicationsData.isEmpty,
                  let decoded = try? JSONDecoder().decode(Set<String>.self, from: readCitedPublicationsData) else {
                return Set<String>()
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                readCitedPublicationsData = encoded
            }
        }
    }
    
    // 已查看引用列表的论文 clusterId 集合
    private var viewedCitingPaperIds: Set<String> {
        get {
            guard !viewedCitingPapersData.isEmpty,
                  let decoded = try? JSONDecoder().decode(Set<String>.self, from: viewedCitingPapersData) else {
                return Set<String>()
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                viewedCitingPapersData = encoded
            }
        }
    }
    
    // 静态方法，用于从外部获取被引用文章数量（用于 TabView badge）
    // 测试模式：返回所有学者论文列表中实际显示 Badge 的论文数量总和
    static func getCitedPublicationsCount() -> Int {
        var totalCitedCount = 0
        let dataManager = DataManager.shared
        // let citationManager = CitationManager.shared // No longer needed for count
        
        // 获取已查看的 clusterId 集合（从 UserDefaults）
        var viewedIds = Set<String>()
        if let data = UserDefaults.standard.data(forKey: "viewedCitingPapers"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            viewedIds = decoded
        }
        
        print("🔔 [WhoCiteMeView] Calculating badge count. Total scholars: \(dataManager.scholars.count), Viewed IDs count: \(viewedIds.count)")
        
        // 遍历所有学者
        for scholar in dataManager.scholars {
            print("🔔 [WhoCiteMeView] Processing scholar: \(scholar.name) (ID: \(scholar.id))")
            // 统计该学者论文列表中实际显示 Badge 的论文数量
            // 始终使用 UnifiedCacheManager 中的完整数据进行统计
            // CitationManager 中的数据可能是分页的（例如只加载了前20条），会导致统计不准确
            
            // 使用 CitationManager 中的 publicationChanges 计算 Badge
            // Badge 显示的是新增引用数（Growth）
            let badgeCount = CitationManager.shared.publicationChanges[scholar.id]?.totalNewCitations ?? 0
            
            print("🔔 [WhoCiteMeView] Scholar \(scholar.name): \(badgeCount) new citations (growth)")
            totalCitedCount += badgeCount
            print("🔔 [WhoCiteMeView] Running total after \(scholar.name): \(totalCitedCount)")
        }
        
        print("🔔 [WhoCiteMeView] ✅ FINAL Total badge count across all \(dataManager.scholars.count) scholars: \(totalCitedCount)")
        return totalCitedCount
    }
    
    // 排序后的学者列表：将 "it's me" 的学者排在第一位
    private var sortedScholars: [Scholar] {
        let scholars = dataManager.scholars
        guard let myScholarId = confirmedMyScholarId else {
            return scholars
        }
        
        // 分离 "it's me" 的学者和其他学者
        var myScholar: Scholar?
        var otherScholars: [Scholar] = []
        
        for scholar in scholars {
            if scholar.id == myScholarId {
                myScholar = scholar
            } else {
                otherScholars.append(scholar)
            }
        }
        
        // 将 "it's me" 的学者放在第一位
        if let myScholar = myScholar {
            return [myScholar] + otherScholars
        } else {
            return scholars
        }
    }
    
    // Conditionally wraps the content in its own NavigationView. When embedded in
    // the Scholars tab (`embeddedScholar != nil`) the parent already provides a
    // navigation context, so we skip our own to avoid a nested/duplicate nav bar
    // (which would show a spurious back button).
    @ViewBuilder
    private var mainContent: some View {
        if embeddedScholar != nil {
            innerContent
        } else {
            NavigationView {
                innerContent
            }
            .navigationViewStyle(.stack)
        }
    }

    private var innerContent: some View {
        VStack(spacing: 0) {
            if dataManager.scholars.isEmpty {
                emptyStateView
            } else {
                // 学者选择器（嵌入 Scholars 时隐藏，固定为点进来的那位学者）
                if embeddedScholar == nil {
                    scholarPicker
                }

                if let scholar = selectedScholar {
                    // 内容区域
                    contentView(for: scholar)
                } else {
                    selectScholarPrompt
                }
            }
        }
        .navigationTitle(embeddedScholar?.displayName ?? "who_cite_me".localized)
        .navigationBarTitleDisplayMode(embeddedScholar == nil ? .automatic : .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // 只保留排序按钮
                if selectedScholar != nil {
                    sortButtonToolbar(for: selectedScholar!.id)
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            CitationFilterView(filter: $currentFilter)
        }
        .sheet(isPresented: $showingExportSheet) {
            exportOptionsView
        }
        .sheet(isPresented: $showingCitedPublicationsSheet) {
            citedPublicationsSheetView
        }
    }

    var body: some View {
        // Agent feature: gated behind Google sign-in. The data-loading modifiers below
        // live on `gatedContent`, so they only run once the user is signed in.
        AgentSignInGate(
            icon: "quote.bubble",
            title: "who_cite_me".localized,
            subtitle: "whocited_signin_subtitle".localized,
            desc: "whocited_signin_desc".localized
        ) {
            gatedContent
        }
    }

    private var gatedContent: some View {
        mainContent
        .onAppear {
            if let embedded = embeddedScholar {
                // 嵌入模式：固定为点进来的那位学者
                if selectedScholar?.id != embedded.id {
                    selectedScholar = embedded
                    loadData(for: embedded)
                }
            } else if selectedScholar == nil {
                // 优先选择 "it's me" 的学者，否则选择第一个
                let firstScholar: Scholar?
                if let myScholarId = confirmedMyScholarId,
                   let myScholar = dataManager.scholars.first(where: { $0.id == myScholarId }) {
                    firstScholar = myScholar
                } else {
                    firstScholar = sortedScholars.first
                }

                if let firstScholar = firstScholar {
                    selectedScholar = firstScholar
                    loadData(for: firstScholar)
                }
            }

            // 更新被引用文章数量（包括导航栏 Badge）
            updateCitedPublicationsCount()

            // 确保在视图出现时也更新一次 Badge
            Task { @MainActor in
                badgeCountManager.updateCount()
            }
        }
        .onChange(of: dataManager.scholars) { _, _ in
            // 当学者列表变化时，更新被引用文章数量
            updateCitedPublicationsCount()
            // 同时更新导航栏 Badge
            Task { @MainActor in
                badgeCountManager.updateCount()
            }
        }
        .onChange(of: selectedScholar) { _, _ in
            // 当选择的学者变化时，更新被引用文章数量
            updateCitedPublicationsCount()
        }
        .onReceive(UnifiedCacheManager.shared.dataChangePublisher) { change in
            // 当缓存数据变化时，更新被引用文章数量
            switch change {
            case .publicationsUpdated, .newPublicationsDetected:
                updateCitedPublicationsCount()
                // 同时更新导航栏 Badge
                Task { @MainActor in
                    badgeCountManager.updateCount()
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("showCitationNotification"))) { notification in
            // 处理通知点击，跳转到引用文章页面
            print("📱 [WhoCiteMeView] Received showCitationNotification")
            if let userInfo = notification.userInfo,
               let clusterId = userInfo["cluster_id"] as? String,
               let scholarId = userInfo["scholar_id"] as? String,
               let publicationTitle = userInfo["publication_title"] as? String {
                
                print("📱 [WhoCiteMeView] Processing notification: clusterId=\(clusterId), scholarId=\(scholarId), title=\(publicationTitle)")
                
                // 切换到 Who Cite Me 标签页（标签页索引是 3）
                NotificationCenter.default.post(name: Notification.Name("switchToWhoCiteMeTab"), object: nil)
                
                // 选择对应的学者
                if let scholar = dataManager.scholars.first(where: { $0.id == scholarId }) {
                    print("📱 [WhoCiteMeView] Found scholar: \(scholar.name)")
                    selectedScholar = scholar
                    
                    // 先尝试从缓存中查找论文
                    var foundPublication: PublicationDisplay? = nil
                    if let publications = UnifiedCacheManager.shared.getPublications(
                        scholarId: scholarId,
                        sortBy: "total", // 默认按引用数排序
                        startIndex: 0,
                        limit: Int.max
                    ) {
                        // 查找匹配的论文
                        if let matchedPub = publications.first(where: { $0.clusterId == clusterId }) {
                            foundPublication = PublicationDisplay(
                                id: matchedPub.id,
                                title: matchedPub.title,
                                clusterId: matchedPub.clusterId,
                                citationCount: matchedPub.citationCount,
                                year: matchedPub.year
                            )
                            print("📱 [WhoCiteMeView] Found publication in cache: \(matchedPub.title)")
                        }
                    }
                    
                    // 如果缓存中没有，使用通知中的信息创建
                    if foundPublication == nil {
                        print("⚠️ [WhoCiteMeView] Publication not found in cache, using notification data")
                        foundPublication = PublicationDisplay(
                            id: clusterId,
                            title: publicationTitle,
                            clusterId: clusterId,
                            citationCount: nil,
                            year: nil
                        )
                    }
                    
                    // 加载数据并打开引用文章页面
                    loadData(for: scholar)
                    
                    // 等待数据加载完成后，打开引用文章页面
                    Task { @MainActor in
                        // 等待数据加载完成（最多等待5秒）
                        var attempts = 0
                        var publicationReady = false
                        
                        while attempts < 50 && !publicationReady {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 等待 0.1 秒
                            attempts += 1
                            
                            // 检查数据是否已加载（通过检查 citationManager 是否有数据）
                            if let publications = citationManager.scholarPublications[scholarId],
                               !publications.isEmpty {
                                publicationReady = true
                                print("📱 [WhoCiteMeView] Data loaded after \(attempts * 100)ms")
                            }
                        }
                        
                        // 再次尝试从 UnifiedCacheManager 获取完整的论文信息
                        if let publications = UnifiedCacheManager.shared.getPublications(
                            scholarId: scholarId,
                            sortBy: "total",
                            startIndex: 0,
                            limit: Int.max
                        ) {
                            if let matchedPub = publications.first(where: { $0.clusterId == clusterId }) {
                                foundPublication = PublicationDisplay(
                                    id: matchedPub.id,
                                    title: matchedPub.title,
                                    clusterId: matchedPub.clusterId,
                                    citationCount: matchedPub.citationCount,
                                    year: matchedPub.year
                                )
                                print("📱 [WhoCiteMeView] Updated publication info from cache: \(matchedPub.title)")
                            }
                        }
                        
                        // 打开引用文章页面
                        if let publication = foundPublication {
                            print("📱 [WhoCiteMeView] Opening citing papers sheet for: \(publication.title)")
                            selectedPublication = publication
                            loadCitingPapers(for: publication)
                        } else {
                            print("❌ [WhoCiteMeView] Failed to create publication object")
                        }
                    }
                } else {
                    print("❌ [WhoCiteMeView] Scholar not found: \(scholarId)")
                }
            } else {
                print("❌ [WhoCiteMeView] Invalid notification userInfo: \(notification.userInfo ?? [:])")
            }
        }
        .onChange(of: confirmedMyScholarId) { _, _ in
            // 当 "it's me" 改变时，重新选择学者（嵌入模式固定学者，不切换）
            guard embeddedScholar == nil else { return }
            if let myScholarId = confirmedMyScholarId,
               let myScholar = dataManager.scholars.first(where: { $0.id == myScholarId }) {
                selectedScholar = myScholar
                loadData(for: myScholar)
            }
        }
        .onChange(of: currentFilter) { _, newFilter in
            applyFilter(newFilter)
        }
    }
    
    // MARK: - Scholar Picker
    
    private var scholarPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
            ForEach(sortedScholars) { scholar in
                    scholarChip(scholar)
            }
        }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }
    
    private func scholarChip(_ scholar: Scholar) -> some View {
        let isSelected = selectedScholar?.id == scholar.id
        let isMyScholar = scholar.id == confirmedMyScholarId
        // 使用 CitationManager 中的 publicationChanges 计算 Badge
        let badgeCount = citationManager.publicationChanges[scholar.id]?.totalNewCitations ?? 0
        
        // 获取该学者的被引用文章列表（未读的，用于点击 Badge 时显示）
        let unreadCitedPublications = getUnreadCitedPublications(scholarId: scholar.id)
        
        return Button(action: {
            // 切换学者时，不要清空数据，直接加载（避免统计数据被错误清零）
            // 数据加载逻辑会在内部处理是否需要清空
            if selectedScholar?.id != scholar.id {
                // 切换学者：直接加载数据，不清空（避免统计数据丢失）
                selectedScholar = scholar
                loadData(for: scholar)
            } else {
                // 点击同一个学者：重新加载数据
                selectedScholar = scholar
                loadData(for: scholar)
            }
        }) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    // 学者头像占位符
                    Circle()
                        .fill(isSelected ? Color.blue : (isMyScholar ? Color.green.opacity(0.3) : Color(.systemGray5)))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(scholar.name.prefix(1)).uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(isSelected ? .white : (isMyScholar ? .green : .secondary))
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(scholar.displayName)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundColor(isSelected ? .blue : .primary)
                                .lineLimit(1)
                            
                            if isMyScholar {
                                Text("(" + "its_me".localized + ")")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        if let stats = citationManager.statistics[scholar.id] {
                            Text("\(stats.totalCitingPapers) \("citations".localized)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.blue.opacity(0.1) : (isMyScholar ? Color.green.opacity(0.1) : Color(.systemGray6)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.blue : (isMyScholar ? Color.green.opacity(0.5) : Color.clear), lineWidth: 1.5)
                )
                
                // 右上角角标（显示该学者论文列表中实际显示 Badge 的论文数量）
                // 测试模式：统计该学者论文列表中实际显示 Badge 的论文数量（每篇论文算1个）
                if badgeCount > 0 {
                    DraggableBadge(count: badgeCount) {
                        // 拖拽消除：清除该学者的所有新增引用记录
                        citationManager.publicationChanges.removeValue(forKey: scholar.id)
                        // 触发UI更新
                        Task { @MainActor in
                            badgeCountManager.updateCount()
                        }
                    }
                    .offset(x: 4, y: -4)
                    .onTapGesture {
                        // 点击 Badge，显示被引用论文列表（显示所有有引用的论文）
                        selectedScholarForBadge = scholar
                        // 获取该学者的所有被引用论文（有引用的论文）
                        if let allCitedPublications = getAllCitedPublications(scholarId: scholar.id) {
                            citedPublicationsForScholar = allCitedPublications
                        } else {
                            citedPublicationsForScholar = unreadCitedPublications
                        }
                        showingCitedPublicationsSheet = true
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    /// 获取指定学者的被引用文章数量（所有论文的引用数量总和）
    private func getScholarCitedCount(scholarId: String) -> Int {
        // 从 UnifiedCacheManager 获取该学者的所有论文（按引用数排序）
        guard let publications = UnifiedCacheManager.shared.getPublications(
            scholarId: scholarId,
            sortBy: "total",
            startIndex: 0,
            limit: Int.max
        ) else {
            return 0
        }
        
        // 计算所有论文的引用数量总和（所有论文的 citationCount 相加）
        var totalCitations = 0
        for publication in publications {
            if let citationCount = publication.citationCount {
                totalCitations += citationCount
            }
        }
        
        return totalCitations
    }
    
    /// 获取指定学者的所有被引用论文列表（有引用的论文）
    private func getAllCitedPublications(scholarId: String) -> [ScholarPublication]? {
        // 从 UnifiedCacheManager 获取该学者的所有论文（按引用数排序）
        guard let publications = UnifiedCacheManager.shared.getPublications(
            scholarId: scholarId,
            sortBy: "total",
            startIndex: 0,
            limit: Int.max
        ) else {
            return nil
        }
        
        // 筛选有引用的论文（citationCount > 0）
        return publications.filter { publication in
            if let citationCount = publication.citationCount {
                return citationCount > 0
            }
            return false
        }
    }
    
    /// 获取指定学者的未读被引用文章列表
    private func getUnreadCitedPublications(scholarId: String) -> [ScholarPublication] {
        // 从 UnifiedCacheManager 获取该学者的所有论文（按引用数排序）
        guard let publications = UnifiedCacheManager.shared.getPublications(
            scholarId: scholarId,
            sortBy: "total",
            startIndex: 0,
            limit: Int.max
        ) else {
            return []
        }
        
        // 获取已读的 clusterId 集合
        let readIds = readCitedPublicationIds
        
        // 筛选有引用的论文（citationCount > 0）且未读的
        return publications.filter { publication in
            // 必须有引用
            guard let citationCount = publication.citationCount, citationCount > 0 else {
                return false
            }
            
            // 必须有 clusterId
            guard let clusterId = publication.clusterId, !clusterId.isEmpty else {
                return false
            }
            
            // 检查是否已读
            return !readIds.contains(clusterId)
        }
    }
    
    // MARK: - Content View
    
    private func contentView(for scholar: Scholar) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // 论文列表（显示引用数量）
                publicationListView(for: scholar.id)
                    .padding(16)
                    .liquidGlassCard(cornerRadius: 22)
            }
            .padding()
            .iPadReadableWidth()
        }
        .refreshable {
            await refreshData(for: scholar)
        }
        .liquidGlassCanvas()
    }
    
    
    // MARK: - Publication List View
    
    private func publicationListView(for scholarId: String) -> some View {
        // 使用 refreshTrigger 来触发视图刷新
        let _ = refreshTrigger.value
        
        // 直接使用从 Google Scholar 获取的已排序数据
        let publications = (citationManager.scholarPublications[scholarId] ?? []).map { pub in
            PublicationDisplay(
                id: pub.id,
                title: pub.title,
                clusterId: pub.clusterId,
                citationCount: pub.citationCount,
                year: pub.year
            )
        }
        
        let changes = citationManager.publicationChanges[scholarId]
        
        return VStack(alignment: .leading, spacing: 12) {
            // 标题行
            HStack {
                Text("publication_list".localized)
                    .font(.headline)
                
                Spacer()
                
                if let changes = changes, changes.hasChanges {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("+\(changes.totalNewCitations)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Text("\(publications.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if citationManager.isLoading {
                publicationLoadingView
            } else if publications.isEmpty {
                publicationEmptyView
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(publications) { pub in
                        VStack(spacing: 0) {
                            publicationRow(pub, scholarId: scholarId, changes: changes)
                                .id(pub.id)
                            Divider()
                                .padding(.leading, 4)
                        }
                    }
                    
                    // 加载更多指示器（当滚动到底部时自动触发）
                    if citationManager.hasMorePublications[scholarId] == true {
                        loadMoreView(for: scholarId)
                            .onAppear {
                                // 当加载更多视图出现时，触发加载（模拟点击"Show more"）
                                loadMorePublications(for: scholarId)
                            }
                    } else if citationManager.isLoadingMore {
                        loadMoreView(for: scholarId)
                    }
                }
            }
        }
        .sheet(item: $selectedPublication) { publication in
            citingPapersSheetView(for: publication)
        }
    }
    
    private func publicationRow(_ publication: PublicationDisplay, scholarId: String, changes: CitationCacheService.PublicationChanges?) -> some View {
        // 检查这篇论文的引用数是否有变化（使用 clusterId 或 title+year 匹配）
        let change = changes?.increased.first { changePub in
            // 优先使用 clusterId 匹配
            if let pubClusterId = publication.clusterId,
               let changeClusterId = changePub.publication.clusterId,
               !pubClusterId.isEmpty, !changeClusterId.isEmpty {
                return pubClusterId == changeClusterId
            }
            // 后备：使用 title + year 匹配
            return changePub.publication.title == publication.title &&
                   changePub.publication.year == publication.year
        }
        
        return HStack(spacing: 8) {
            // 左侧主要内容
            VStack(alignment: .leading, spacing: 6) {
                // 标题
                Text(publication.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 元数据 - 左对齐
                HStack(spacing: 16) {
                    if let year = publication.year {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(year))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                if let citationCount = publication.citationCount, let _ = publication.clusterId {
                    // 可点击的引用数 - 立即显示sheet，不等待数据加载
                    Button(action: {
                        // 立即设置加载状态，确保sheet显示时用户看到加载动画而不是错误
                        isLoadingCitingPapers = true
                        citingPapersError = nil
                        citingPapers = []
                        
                        selectedPublication = publication
                        showingCitingPapersSheet = true
                        // 加载数据
                        loadCitingPapers(for: publication)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "quote.bubble")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("\(citationCount)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .underline()
                        }
                    }
                    .disabled(citationCount == 0)
                } else if let citationCount = publication.citationCount {
                        HStack(spacing: 4) {
                            Image(systemName: "quote.bubble")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(citationCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            // 右侧：Badge 和变化标记
            HStack(spacing: 4) {
                // Badge：显示新增引用数（Growth）
                // 只有当该论文有新增引用时才显示
                if let clusterId = publication.clusterId,
                   let changes = citationManager.publicationChanges[scholarId],
                   let change = changes.increased.first(where: { $0.publication.clusterId == clusterId }),
                   change.delta > 0 {
                    DraggableBadge(count: change.delta) {
                        // 拖拽消除：清除该论文的新增引用记录
                        // 注意：这里我们不能只清除单个论文的记录，因为 publicationChanges 是整体结构
                        // 我们可以更新 publicationChanges，移除该论文的记录
                        if let currentChanges = citationManager.publicationChanges[scholarId] {
                            // 重新构建 increased 列表，移除当前论文
                            let newIncreased = currentChanges.increased.filter { $0.publication.clusterId != clusterId }
                            let newChanges = CitationCacheService.PublicationChanges(
                                increased: newIncreased,
                                decreased: currentChanges.decreased,
                                newPublications: currentChanges.newPublications
                            )
                            citationManager.publicationChanges[scholarId] = newChanges
                        }
                        
                        // 触发UI更新
                        updateCitedPublicationsCount()
                        Task { @MainActor in
                            badgeCountManager.updateCount()
                        }
                    }
                    .padding(.trailing, 4)
                }
                
                // 变化标记
                if let change = change, change.delta > 0 {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("+\(change.delta)")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
    
    private var publicationLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("loading".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var publicationEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("no_publications_found".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    /// 加载更多视图
    private func loadMoreView(for scholarId: String) -> some View {
        VStack(spacing: 12) {
            if citationManager.isLoadingMore {
                ProgressView()
                    .scaleEffect(0.8)
                Text("loading_more".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("load_more".localized)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Summary Stats Card
    
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("no_scholars_added".localized)
                .font(.headline)
            
            Text("add_scholar_first".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var selectScholarPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("select_scholar_above".localized)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Toolbar Buttons
    
    // Toolbar 排序按钮（显示在导航栏右上角）
    private func sortButtonToolbar(for scholarId: String) -> some View {
        Menu {
            ForEach(PublicationSortOption.allCases, id: \.self) { option in
                Button(action: {
                    // 切换排序选项
                    // 如果切换的是不同的排序，立即清空显示，然后 Fetch
                    if sortOption != option {
                        sortOption = option
                        
                        // 立即清空当前显示，避免显示错误排序的数据
                        citationManager.scholarPublications[scholarId] = []
                        
                        // 重新请求数据（使用 Google Scholar 的排序参数）
                        let sortParam = option.googleScholarParam ?? "total"
                        citationManager.fetchScholarPublications(
                            for: scholarId,
                            sortBy: sortParam,
                            forceRefresh: false
                        )
                    }
                }) {
                    HStack {
                        Image(systemName: option.icon)
                        Text(option.title)
                        
                        if sortOption == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .disabled(citationManager.isLoading)
    }
    
    // 内联排序按钮（显示在列表标题右侧）- 已废弃，保留以防需要
    private func sortButtonInline(for scholarId: String) -> some View {
        Menu {
            ForEach(PublicationSortOption.allCases, id: \.self) { option in
                Button(action: {
                    // 切换排序选项
                    sortOption = option
                    
                    // 重新请求数据（使用 Google Scholar 的排序参数）
                    let sortParam = option.googleScholarParam
                    citationManager.fetchScholarPublications(
                        for: scholarId,
                        sortBy: sortParam,
                        forceRefresh: false
                    )
                }) {
                    HStack {
                        Image(systemName: option.icon)
                        Text(option.title)
                        
                        if sortOption == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .disabled(citationManager.isLoading)
    }
    
    private var filterButton: some View {
        Button(action: {
            showingFilterSheet = true
        }) {
            Image(systemName: currentFilter.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .disabled(selectedScholar == nil)
    }
    
    private var exportButton: some View {
        Button(action: {
            showingExportSheet = true
        }) {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(selectedScholar == nil || filteredPapers.isEmpty)
    }
    
    private var refreshButton: some View {
        Button(action: {
            if let scholar = selectedScholar {
                citationManager.refreshAllData(for: scholar.id)
            }
        }) {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(selectedScholar == nil || citationManager.isLoading)
    }
    
    // MARK: - Export Options
    
    private var exportOptionsView: some View {
        NavigationView {
            List {
                ForEach(CitationExportService.ExportFormat.allCases, id: \.self) { format in
                    Button(action: {
                        exportData(format: format)
                    }) {
                        HStack {
                            Text("export_\(format.rawValue.lowercased())".localized)
                            Spacer()
                            Image(systemName: "doc.text")
                        }
                    }
                }
            }
            .liquidGlassCanvas()
            .navigationTitle("export_format".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("cancel".localized) {
                        showingExportSheet = false
                    }
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadData(for scholar: Scholar) {
        // 使用当前选择的排序选项
        let sortParam = sortOption.googleScholarParam
        citationManager.fetchScholarPublications(for: scholar.id, sortBy: sortParam, forceRefresh: false)
    }
    
    /// 加载更多论文
    private func loadMorePublications(for scholarId: String) {
        let sortParam = sortOption.googleScholarParam
        citationManager.loadMorePublications(for: scholarId, sortBy: sortParam)
    }
    
    private func refreshData(for scholar: Scholar) async {
        // 下拉刷新时强制刷新缓存，获取最新数据
        let sortParam = sortOption.googleScholarParam
        citationManager.fetchScholarPublications(for: scholar.id, sortBy: sortParam, forceRefresh: true)
        
        // 等待数据加载完成（等待 isLoading 变为 false）
        while citationManager.isLoading {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 等待 0.1 秒
        }
    }
    
    private func updateFilteredPapers(for scholarId: String) {
        let papers = citationManager.citingPapers[scholarId] ?? []
        filteredPapers = citationManager.applyFilter(currentFilter, to: papers)
    }
    
    private func applyFilter(_ filter: CitationFilter) {
        if let scholar = selectedScholar {
            updateFilteredPapers(for: scholar.id)
        }
    }
    
    // MARK: - Sorting
    // 注意：排序现在由 Google Scholar 服务器端完成，我们只需要传递 sortby 参数
    
    // MARK: - Export
    
    private func exportData(format: CitationExportService.ExportFormat) {
        guard let scholar = selectedScholar else { return }
        
        if let result = citationManager.exportData(
            for: scholar.id,
            papers: filteredPapers,
            format: format
        ) {
            shareData(result)
        }
        
        showingExportSheet = false
    }
    
    private func shareData(_ result: ExportResult) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(result.fileName)
        
        do {
            try result.data.write(to: tempURL)
            
            let activityVC = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Failed to export: \(error)")
        }
    }
    
    // MARK: - Citing Papers Sheet View
    
    @ViewBuilder
    func citingPapersSheetView(for publication: PublicationDisplay) -> some View {
        CitingPapersSheetContent(
            publication: publication,
            citingPapers: $citingPapers,
            isLoadingCitingPapers: $isLoadingCitingPapers,
            isLoadingMoreCitingPapers: $isLoadingMoreCitingPapers,
            hasMoreCitingPapers: $hasMoreCitingPapers,
            citingPapersError: $citingPapersError,
            sortByDate: $citingPapersSortByDate,
            onDismiss: {
                selectedPublication = nil
                citingPapers = []
                citingPapersError = nil
                hasMoreCitingPapers = false
            },
            onLoadCitingPapers: { loadCitingPapers(for: publication) },
            onLoadMoreCitingPapers: { loadMoreCitingPapers(for: publication) }
        )
    }

    
    // MARK: - Load Citing Papers
    
    private func loadCitingPapers(for publication: PublicationDisplay) {
        guard let clusterId = publication.clusterId else {
            // 不要在这里设置错误，保持加载状态让用户看到我们在尝试
            // citingPapersError = "无法获取引用数据：缺少 Cluster ID"
            isLoadingCitingPapers = false
            return
        }
        
        isLoadingCitingPapers = true
        citingPapersError = nil
        citingPapers = []
        hasMoreCitingPapers = false
        
        // 不再使用缓存优先的策略，总是重新获取以确保用户看到加载动画
        // 这提供更好的用户体验，让用户知道我们正在主动获取数据
        
        // 使用统一协调器获取引用文章（第一页）
        Task {
            let success = await CitationFetchCoordinator.shared.fetchCitedByPage(
                clusterId: clusterId,
                sortByDate: citingPapersSortByDate,
                startIndex: 0,
                priority: .high
            )
            
            await MainActor.run {
                isLoadingCitingPapers = false
                
                if success {
                    // 从缓存获取数据
                    let cacheService = CitationCacheService.shared
                    if let papers = cacheService.getCachedCitingPapersList(for: clusterId, sortByDate: citingPapersSortByDate, startIndex: 0) {
                        citingPapers = papers
                        hasMoreCitingPapers = papers.count >= 10
                        // 不再显示错误，即使数据为空也只显示空状态
                    }
                    // 如果缓存为空，也不显示错误，只显示空状态
                }
                // 如果获取失败，也不显示错误，让用户看到空状态和重试按钮
            }
        }
    }
    
    private func loadMoreCitingPapers(for publication: PublicationDisplay) {
        guard let clusterId = publication.clusterId else { return }
        guard !isLoadingMoreCitingPapers && hasMoreCitingPapers else { return }
        
        isLoadingMoreCitingPapers = true
        let startIndex = citingPapers.count
        
        // 先检查缓存
        let cacheService = CitationCacheService.shared
        if let cachedPapers = cacheService.getCachedCitingPapersList(for: clusterId, sortByDate: citingPapersSortByDate, startIndex: startIndex) {
            // 使用缓存数据
            citingPapers.append(contentsOf: cachedPapers)
            hasMoreCitingPapers = cachedPapers.count >= 10
            isLoadingMoreCitingPapers = false
            
            // 在后台静默更新（使用统一协调器）
            Task {
                _ = await CitationFetchCoordinator.shared.fetchCitedByPage(
                    clusterId: clusterId,
                    sortByDate: citingPapersSortByDate,
                    startIndex: startIndex,
                    priority: .medium
                )
                // 从缓存获取更新后的数据
                if let updatedPapers = cacheService.getCachedCitingPapersList(for: clusterId, sortByDate: citingPapersSortByDate, startIndex: startIndex) {
                    await MainActor.run {
                        if updatedPapers != cachedPapers {
                            // 移除旧的缓存数据，添加新数据
                            let oldCount = self.citingPapers.count - cachedPapers.count
                            self.citingPapers = Array(self.citingPapers.prefix(oldCount))
                            self.citingPapers.append(contentsOf: updatedPapers)
                            self.hasMoreCitingPapers = updatedPapers.count >= 10
                        }
                    }
                }
            }
            return
        }
        
        // 使用统一协调器获取更多引用文章
        Task {
            let success = await CitationFetchCoordinator.shared.fetchCitedByPage(
                clusterId: clusterId,
                sortByDate: citingPapersSortByDate,
                startIndex: startIndex,
                priority: .high
            )
            
            await MainActor.run {
                isLoadingMoreCitingPapers = false
                
                if success {
                    // 从缓存获取数据
                    if let papers = cacheService.getCachedCitingPapersList(for: clusterId, sortByDate: citingPapersSortByDate, startIndex: startIndex) {
                        if !papers.isEmpty {
                            citingPapers.append(contentsOf: papers)
                            hasMoreCitingPapers = papers.count >= 10
                        } else {
                            hasMoreCitingPapers = false
                        }
                    } else {
                        hasMoreCitingPapers = false
                    }
                } else {
                    // 统一错误信息，明确说明是反爬虫机制
                    citingPapersError = "anti_bot_restriction_message".localized
                    hasMoreCitingPapers = false
                }
            }
        }
    }
    
    // MARK: - Update Cited Publications Count
    
    /// 更新被引用文章数量（测试模式：统计所有学者论文列表中实际显示 Badge 的论文数量总和）
    private func updateCitedPublicationsCount() {
        Task { @MainActor in
            // 使用静态方法获取正确的计数（基于 UnifiedCacheManager）
            let totalCitedCount = WhoCiteMeView.getCitedPublicationsCount()
            
            citedPublicationsCount = totalCitedCount
            // 同时更新共享的 Badge 计数（用于导航栏）
            badgeCountManager.count = totalCitedCount
            print("📊 [WhoCiteMeView] Updated cited publications count: \(totalCitedCount), badge count: \(totalCitedCount)")
        }
    }
    
    // MARK: - Cited Publications Sheet
    
    /// 被引用论文列表 Sheet
    private var citedPublicationsSheetView: some View {
        NavigationView {
            List {
                if let scholar = selectedScholarForBadge {
                    Section(header: Text(String(format: "whocite_scholar_cited".localized, scholar.displayName))) {
                        ForEach(citedPublicationsForScholar) { publication in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(publication.title)
                                    .font(.headline)

                                HStack {
                                    if let citationCount = publication.citationCount {
                                        Label(String(format: "whocite_n_citations".localized, citationCount), systemImage: "quote.bubble")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let year = publication.year {
                                        Label("\(year)", systemImage: "calendar")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    Text("whocite_no_unread".localized)
                        .foregroundColor(.secondary)
                }
            }
            .liquidGlassCanvas()
            .navigationTitle("whocite_cited_pubs".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localized) {
                        // 标记所有显示的论文为已读
                        markPublicationsAsRead(citedPublicationsForScholar)
                        showingCitedPublicationsSheet = false
                    }
                }
            }
        }
    }
    
    /// 标记论文为已读
    @MainActor
    private func markPublicationsAsRead(_ publications: [ScholarPublication]) {
        var readIds = readCitedPublicationIds
        
        for publication in publications {
            if let clusterId = publication.clusterId, !clusterId.isEmpty {
                readIds.insert(clusterId)
            }
        }
        
        // 更新已读状态
        if let encoded = try? JSONEncoder().encode(readIds) {
            readCitedPublicationsData = encoded
        }
        
        print("📖 [WhoCiteMeView] Marked \(publications.count) publications as read")
        
        
        // 更新角标显示
        updateCitedPublicationsCount()
    }
    
    // MARK: - Helper Methods
    
    // 标记论文为已读的方法已移除,因为现在使用 publicationChanges 跟踪增长
}

// MARK: - Citing Papers Sheet Content
struct CitingPapersSheetContent: View {
    let publication: PublicationDisplay
    @Binding var citingPapers: [CitingPaper]
    @Binding var isLoadingCitingPapers: Bool
    @Binding var isLoadingMoreCitingPapers: Bool
    @Binding var hasMoreCitingPapers: Bool
    @Binding var citingPapersError: String?
    @Binding var sortByDate: Bool
    let onDismiss: () -> Void
    let onLoadCitingPapers: () -> Void
    let onLoadMoreCitingPapers: () -> Void
    
    @State private var selectedCitingPaper: CitingPaper?
    
    var body: some View {
        NavigationView {
            Group {
                if let selectedPaper = selectedCitingPaper {
                    // 显示文章详情
                    citingPaperDetailView(for: selectedPaper)
                } else {
                    // 显示引用文章列表
                    VStack(spacing: 0) {
                        // 论文信息头部
                        publicationHeaderView(for: publication)

                        // 引用文章内容
                        if isLoadingCitingPapers {
                            // 加载中：优先显示加载视图
                            citingPapersLoadingView
                        } else if let error = citingPapersError, citingPapers.isEmpty {
                            // 有错误且没有数据时显示错误视图
                            citingPapersErrorView(error)
                        } else if citingPapers.isEmpty && citingPapersError == nil {
                            // 没有数据且没有错误时显示空视图
                            citingPapersEmptyView
                        } else {
                            // 有数据时显示列表（错误会在列表下方显示）
                            citingPapersListViewWithError
                        }
                    }
                }
            }
            .liquidGlassCanvas()
            .navigationTitle(selectedCitingPaper == nil ? String(format: "whocite_citing_n".localized, citingPapers.count) : "whocite_article_detail".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedCitingPaper != nil {
                        Button("back".localized) {
                            selectedCitingPaper = nil
                        }
                    } else {
                        // 排序按钮
                        Menu {
                            Button(action: {
                                sortByDate = true
                                onLoadCitingPapers()
                            }) {
                                HStack {
                                    Text("sort_by_date".localized)
                                    if sortByDate {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Button(action: {
                                sortByDate = false
                                onLoadCitingPapers()
                            }) {
                                HStack {
                                    Text("sort_by_relevance".localized)
                                    if !sortByDate {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("close".localized) {
                        selectedCitingPaper = nil
                        onDismiss()
                    }
                }
            }
            // 移除 .onAppear 调用，因为按钮点击时已经调用了 loadCitingPapers
            // 避免重复调用导致状态混乱
        }
    }
    
    // MARK: - Publication Header
    
    private func publicationHeaderView(for publication: PublicationDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(publication.title)
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 16) {
                if let year = publication.year {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(String(year))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let citationCount = publication.citationCount {
                    HStack(spacing: 4) {
                        Image(systemName: "quote.bubble")
                            .font(.caption2)
                        Text(String(format: "citations_count".localized, citationCount))
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassSurface(cornerRadius: 18)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Citing Papers List
    
    private var citingPapersListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(citingPapers) { paper in
                    VStack(spacing: 0) {
                        citingPaperRowView(paper)
                        Divider()
                            .padding(.leading, 16)
                    }
                }
                
                // 加载更多视图
                if hasMoreCitingPapers {
                    loadMoreCitingPapersView
                        .onAppear {
                            onLoadMoreCitingPapers()
                        }
                }
            }
        }
    }
    
    // 带错误提示的列表视图（在已有内容下方显示错误）
    private var citingPapersListViewWithError: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 已加载的文章列表
                ForEach(citingPapers) { paper in
                    VStack(spacing: 0) {
                        citingPaperRowView(paper)
                        Divider()
                            .padding(.leading, 16)
                    }
                }
                
                // 加载更多视图
                if hasMoreCitingPapers && citingPapersError == nil {
                    loadMoreCitingPapersView
                        .onAppear {
                            onLoadMoreCitingPapers()
                        }
                }
                
                // 错误提示（在已有内容下方显示）
                if let error = citingPapersError {
                    citingPapersInlineErrorView(error)
                }
            }
        }
    }
    
    private var loadMoreCitingPapersView: some View {
        VStack(spacing: 12) {
            if isLoadingMoreCitingPapers {
                ProgressView()
                    .scaleEffect(1.0)
                Text("loading_more".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button(action: {
                    onLoadMoreCitingPapers()
                }) {
                    Text("load_more".localized)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    private func citingPaperRowView(_ paper: CitingPaper) -> some View {
        Button(action: {
            selectedCitingPaper = paper
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // 标题
                Text(paper.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                
                // 作者
                if !paper.authors.isEmpty {
                    Text(paper.authors.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 元数据
                HStack(spacing: 12) {
                    if let year = paper.year {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(String(year))
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if let venue = paper.venue, !venue.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "building.2")
                                .font(.caption2)
                            Text(venue)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if let citationCount = paper.citationCount {
                        HStack(spacing: 4) {
                            Image(systemName: "quote.bubble")
                                .font(.caption2)
                            Text("\(citationCount)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Loading/Error/Empty Views
    
    private var citingPapersLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("fetching_citing_papers".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("this_may_take_a_few_seconds".localized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // 全屏错误视图（用于初始加载失败且没有数据时）
    private func citingPapersErrorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("load_failed".localized)
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // 按钮组
            VStack(spacing: 12) {
                Button(action: {
                    onLoadCitingPapers()
                }) {
                    Label("retry".localized, systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                
                // 在浏览器中打开按钮
                if let clusterId = publication.clusterId {
                    Button(action: {
                        let urlString = "https://scholar.google.com/scholar?hl=en&cites=\(clusterId)"
                        guard let url = URL(string: urlString) else { return }
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #endif
                    }) {
                        Label("open_in_browser".localized, systemImage: "safari")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // 内联错误视图（在已有内容下方显示）
    private func citingPapersInlineErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Divider()
            
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("load_failed".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("anti_bot_restriction_message".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            
            // 操作按钮
            HStack(spacing: 12) {
                Button(action: {
                    // 清除错误，重试加载
                    DispatchQueue.main.async {
                        citingPapersError = nil
                        if citingPapers.isEmpty {
                            onLoadCitingPapers()
                        } else {
                            onLoadMoreCitingPapers()
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("retry".localized)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                // 在浏览器中打开按钮
                if let clusterId = publication.clusterId {
                    Button(action: {
                        let urlString = "https://scholar.google.com/scholar?hl=en&cites=\(clusterId)"
                        guard let url = URL(string: urlString) else { return }
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #endif
                    }) {
                        HStack {
                            Image(systemName: "safari")
                            Text("open_in_browser".localized)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
    
    private var citingPapersEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("no_citing_papers_found".localized)
                .font(.headline)
            
            Text("no_citing_papers_reasons".localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Citing Paper Detail View
    
    @ViewBuilder
    func citingPaperDetailView(for paper: CitingPaper) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题
                Text(paper.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                // 作者
                if !paper.authors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("author".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(paper.authors.joined(separator: ", "))
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                
                // 元数据
                VStack(alignment: .leading, spacing: 12) {
                    if let year = paper.year {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                            Text("year".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(year))
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    if let venue = paper.venue, !venue.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "building.2")
                                .foregroundColor(.secondary)
                            Text("venue".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(venue)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    if let citationCount = paper.citationCount {
                        HStack(spacing: 8) {
                            Image(systemName: "quote.bubble")
                                .foregroundColor(.blue)
                            Text("citation_count".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(citationCount)")
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Divider()
                
                // 摘要
                if let abstract = paper.abstract, !abstract.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("abstract".localized)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(abstract)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Citation Context — verbatim text from Semantic Scholar
                Divider()
                CitationContextSection(citingPaper: paper, myPaperTitle: publication.title)

                Divider()

                // 操作按钮
                VStack(spacing: 12) {
                    if let scholarUrl = paper.scholarUrl, let url = URL(string: scholarUrl) {
                        Button(action: {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #endif
                        }) {
                            HStack {
                                Image(systemName: "safari")
                                Text("view_on_google_scholar".localized)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.body)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                    
                    if let pdfUrl = paper.pdfUrl, let url = URL(string: pdfUrl) {
                        Button(action: {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #endif
                        }) {
                            HStack {
                                Image(systemName: "doc.fill")
                                Text("view_pdf".localized)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.body)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Draggable Badge
struct DraggableBadge: View {
    let count: Int
    let onClear: () -> Void
    
    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .opacity(opacity)
                    .offset(offset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                isDragging = true
                                offset = gesture.translation
                                
                                // 拖拽过程中透明度变化
                                let distance = sqrt(pow(gesture.translation.width, 2) + pow(gesture.translation.height, 2))
                                if distance > 20 {
                                    opacity = max(0, 1 - Double((distance - 20) / 50))
                                }
                            }
                            .onEnded { gesture in
                                let distance = sqrt(pow(gesture.translation.width, 2) + pow(gesture.translation.height, 2))
                                
                                if distance > 50 {
                                    // 拖拽距离足够，触发清除
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        // 继续沿拖拽方向飞出
                                        offset = CGSize(
                                            width: gesture.translation.width * 5,
                                            height: gesture.translation.height * 5
                                        )
                                        opacity = 0
                                    }
                                    
                                    // 延迟执行清除回调
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        onClear()
                                        // 重置状态（虽然视图可能已经消失）
                                        offset = .zero
                                        opacity = 1.0
                                        isDragging = false
                                    }
                                } else {
                                    // 拖拽距离不够，回弹
                                    withAnimation(.spring()) {
                                        offset = .zero
                                        opacity = 1.0
                                    }
                                    isDragging = false
                                }
                            }
                    )
            }
        }
    }
}

// MARK: - Preview
struct WhoCiteMeView_Previews: PreviewProvider {
    static var previews: some View {
        WhoCiteMeView()
            .environmentObject(DataManager.shared)
            .environmentObject(LocalizationManager.shared)
    }
}
