import Foundation
import Combine

// MARK: - 学者数据服务
/// 专门负责从Google Scholar获取学者数据的服务
/// 职责单一，只负责网络请求和数据解析
public class ScholarDataService: ObservableObject {
    
    // MARK: - Properties
    
    public static let shared = ScholarDataService()
    
    private let urlSession: URLSession
    private let dataManager: NewDataManager
    
    // 请求状态
    @Published public var isLoadingScholar = false
    @Published public var lastRequestTime: Date?
    @Published public var requestCount = 0
    
    // 请求限制
    private let requestThrottle: TimeInterval = 2.0 // 2秒间隔
    private var lastRequestTimestamp: Date = .distantPast
    
    // MARK: - Initialization
    
    private init() {
        // 配置URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.allowsCellularAccess = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
        
        self.dataManager = NewDataManager.shared
    }
    
    // MARK: - 错误类型
    
    public enum ScholarDataError: Error, LocalizedError {
        case invalidURL
        case noData
        case parsingError
        case networkError(Error)
        case rateLimited
        case scholarNotFound
        case invalidScholarId
        case requestThrottled(TimeInterval)
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "无效的URL"
            case .noData:
                return "没有数据返回"
            case .parsingError:
                return "数据解析失败"
            case .networkError(let error):
                return "网络错误: \(error.localizedDescription)"
            case .rateLimited:
                return "请求过于频繁，请稍后再试"
            case .scholarNotFound:
                return "未找到该学者"
            case .invalidScholarId:
                return "无效的学者ID"
            case .requestThrottled(let remaining):
                return "请求被限制，请等待 \(String(format: "%.1f", remaining)) 秒"
            }
        }
    }
    
    // MARK: - 主要方法
    
    /// 获取学者信息并更新数据
    /// - Parameters:
    ///   - id: 学者 Google Scholar ID
    ///   - forceRefresh: 为 true 时忽略最小刷新间隔，强制从网络获取
    public func fetchAndUpdateScholar(id: String, forceRefresh: Bool = false) async throws -> Scholar {
        print("🔍 [ScholarDataService] Fetching scholar: \(id), forceRefresh: \(forceRefresh)")

        // 1. 先检查统一缓存
        if let basicInfo = await UnifiedCacheManager.shared.getScholarBasicInfo(scholarId: id) {
            // 检查数据是否足够新鲜（1小时内），如果是且非强制刷新，直接返回缓存
            let isFresh = await UnifiedCacheManager.shared.isDataFresh(scholarId: id)
            if isFresh && !forceRefresh {
                print("⏳ [ScholarDataService] Data still fresh (within 1h), skipping network request: \(basicInfo.name)")
                var scholar = Scholar(id: id, name: basicInfo.name)
                scholar.citations = basicInfo.citations
                scholar.lastUpdated = basicInfo.lastUpdated
                await dataManager.updateScholar(scholar)
                return scholar
            }

            print("💾 [ScholarDataService] Using unified cache: \(basicInfo.name), \(basicInfo.citations) citations")

            // 使用缓存数据，跳过网络请求
            var scholar = Scholar(id: id, name: basicInfo.name)
            scholar.citations = basicInfo.citations
            scholar.lastUpdated = basicInfo.lastUpdated

            await dataManager.updateScholar(scholar)

            // 添加引用历史记录
            let history = CitationHistory(scholarId: id, citationCount: basicInfo.citations)
            await dataManager.addCitationHistory(history)

            print("✅ [ScholarDataService] Updated from cache: \(basicInfo.name) - \(basicInfo.citations)引用")
            return scholar
        }

        print("🌐 [ScholarDataService] Cache miss, fetching from network")
        
        // 2. 缓存未命中，从网络获取
        // 检查请求限制
        try checkRequestThrottle()
        
        // 开始请求
        await MainActor.run {
            self.isLoadingScholar = true
            self.lastRequestTime = Date()
            // 使用安全的加法，防止溢出
            self.requestCount = min(self.requestCount + 1, Int.max - 1)
        }
        
        defer {
            Task { @MainActor in
                self.isLoadingScholar = false
            }
        }
        
        do {
            // 获取学者信息
            let (name, citations) = try await fetchScholarInfo(for: id)
            
            // 创建更新后的学者对象
            var updatedScholar = Scholar(id: id, name: name)
            updatedScholar.citations = citations
            updatedScholar.lastUpdated = Date()
            
            // 保存到数据管理器
            await dataManager.updateScholar(updatedScholar)
            
            // 添加引用历史记录
            let history = CitationHistory(scholarId: id, citationCount: citations)
            await dataManager.addCitationHistory(history)
            
            print("✅ [ScholarDataService] 更新学者数据成功: \(name) - \(citations)引用")
            
            return updatedScholar
            
        } catch {
            print("❌ [ScholarDataService] 获取学者数据失败: \(error)")
            throw error
        }
    }
    
    /// 批量更新多个学者
    public func fetchAndUpdateScholars(ids: [String]) async -> [Result<Scholar, Error>] {
        var results: [Result<Scholar, Error>] = []
        
        for id in ids {
            do {
                let scholar = try await fetchAndUpdateScholar(id: id)
                results.append(.success(scholar))
                
                // 添加延迟以避免请求过于频繁
                try await Task.sleep(nanoseconds: UInt64(requestThrottle * 1_000_000_000))
                
            } catch {
                results.append(.failure(error))
            }
        }
        
        return results
    }
    
    // MARK: - 私有方法
    
    /// 从Google Scholar获取学者信息
    private func fetchScholarInfo(for scholarId: String) async throws -> (name: String, citations: Int) {
        guard !scholarId.isEmpty else {
            throw ScholarDataError.invalidScholarId
        }
        
        guard let url = URL(string: "https://scholar.google.com/citations?user=\(scholarId)&hl=en") else {
            throw ScholarDataError.invalidURL
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        print("📡 [ScholarDataService] 开始获取学者信息: \(scholarId)")
        
        // 发送请求
        let (data, response) = try await urlSession.data(for: request)
        
        // 检查HTTP状态码
        if let httpResponse = response as? HTTPURLResponse {
            print("📊 [ScholarDataService] HTTP状态码: \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 429:
                throw ScholarDataError.rateLimited
            case 404:
                throw ScholarDataError.scholarNotFound
            case 400...499:
                throw ScholarDataError.scholarNotFound
            case 500...599:
                throw ScholarDataError.networkError(URLError(.badServerResponse))
            default:
                break
            }
        }
        
        // 解析HTML数据
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw ScholarDataError.parsingError
        }
        
        // 解析学者基本信息
        let (name, citations) = try parseScholarData(from: htmlString)
        
        // 同时解析论文列表并保存到统一缓存（最大化利用页面内容）
        Task { @MainActor in
            // 使用 CitationFetchService 解析论文列表
            let publications = CitationFetchService.shared.parseScholarPublications(from: htmlString)
            
            // 提取完整的学者信息（h-index, i10-index）
            // 使用 CitationFetchService 的扩展方法
            let extractedInfo = CitationFetchService.shared.extractScholarFullInfo(from: htmlString)
            
            if !publications.isEmpty || extractedInfo != nil {
                // 保存到统一缓存
                let snapshot = ScholarDataSnapshot(
                    scholarId: scholarId,
                    timestamp: Date(),
                    scholarName: extractedInfo?.name ?? name,
                    totalCitations: extractedInfo?.totalCitations ?? citations,
                    hIndex: extractedInfo?.hIndex,
                    i10Index: extractedInfo?.i10Index,
                    publications: publications,
                    sortBy: "total",  // Dashboard 刷新默认使用 total 排序
                    startIndex: 0,
                    source: .dashboard
                )
                UnifiedCacheManager.shared.saveDataSnapshot(snapshot)
                print("📦 [ScholarDataService] Saved \(publications.count) publications to unified cache from dashboard refresh")
            }
        }
        
        return (name, citations)
    }
    
    /// 解析学者数据
    private func parseScholarData(from html: String) throws -> (name: String, citations: Int) {
        // 解析学者姓名
        let namePattern = #"<div[^>]*id="gsc_prf_in"[^>]*>([^<]+)</div>"#
        guard let nameMatch = html.range(of: namePattern, options: .regularExpression),
              let nameRange = html.range(of: ">([^<]+)<", options: .regularExpression, range: nameMatch) else {
            throw ScholarDataError.parsingError
        }
        
        let nameString = String(html[nameRange])
        let name = nameString.replacingOccurrences(of: ">", with: "").replacingOccurrences(of: "<", with: "")
        
        // 解析引用总数
        let citationPattern = #"<td[^>]*class="gsc_rsb_std"[^>]*>(\d+)</td>"#
        guard let citationMatch = html.range(of: citationPattern, options: .regularExpression),
              let citationRange = html.range(of: ">(\d+)<", options: .regularExpression, range: citationMatch) else {
            throw ScholarDataError.parsingError
        }
        
        let citationString = String(html[citationRange])
        let citationNumberString = citationString.replacingOccurrences(of: ">", with: "").replacingOccurrences(of: "<", with: "")
        
        guard let citations = Int(citationNumberString) else {
            throw ScholarDataError.parsingError
        }
        
        print("✅ [ScholarDataService] 解析成功: \(name) - \(citations)引用")
        return (name, citations)
    }
    
    /// 检查请求限制
    private func checkRequestThrottle() throws {
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTimestamp)
        
        if timeSinceLastRequest < requestThrottle {
            let remaining = requestThrottle - timeSinceLastRequest
            throw ScholarDataError.requestThrottled(remaining)
        }
        
        lastRequestTimestamp = now
    }
    
    // MARK: - 便捷方法
    
    /// 验证学者ID格式
    public func validateScholarId(_ id: String) -> Bool {
        // Google Scholar ID通常是字母数字组合，长度在8-12之间
        let pattern = "^[a-zA-Z0-9_-]{8,12}$"
        return id.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// 从URL提取学者ID
    public func extractScholarId(from url: String) -> String? {
        let patterns = [
            #"user=([a-zA-Z0-9_-]+)"#,  // 标准格式
            #"citations\?user=([a-zA-Z0-9_-]+)"#  // 引用页面格式
        ]
        
        for pattern in patterns {
            if let range = url.range(of: pattern, options: .regularExpression) {
                let match = String(url[range])
                let id = match.replacingOccurrences(of: "user=", with: "")
                    .replacingOccurrences(of: "citations?user=", with: "")
                return id
            }
        }
        
        return nil
    }
    
    /// 获取请求统计信息
    public func getRequestStatistics() -> RequestStatistics {
        return RequestStatistics(
            totalRequests: requestCount,
            lastRequestTime: lastRequestTime,
            isThrottled: Date().timeIntervalSince(lastRequestTimestamp) < requestThrottle,
            remainingThrottleTime: max(0, requestThrottle - Date().timeIntervalSince(lastRequestTimestamp))
        )
    }
}

// MARK: - 统计信息结构
public struct RequestStatistics {
    public let totalRequests: Int
    public let lastRequestTime: Date?
    public let isThrottled: Bool
    public let remainingThrottleTime: TimeInterval
    
    public var description: String {
        return """
        请求统计:
        - 总请求数: \(totalRequests)
        - 最后请求: \(lastRequestTime?.formatted() ?? "从未")
        - 被限制: \(isThrottled)
        - 剩余限制时间: \(String(format: "%.1f", remainingThrottleTime))秒
        """
    }
}

// MARK: - 便捷扩展
public extension ScholarDataService {
    
    /// 刷新所有已有学者的数据
    func refreshAllExistingScholars() async -> [Result<Scholar, Error>] {
        let existingScholars = await dataManager.scholars
        let ids = existingScholars.map { $0.id }
        
        print("🔄 [ScholarDataService] 开始刷新 \(ids.count) 个学者的数据")
        
        let results = await fetchAndUpdateScholars(ids: ids)
        
        let successCount = results.filter { if case .success = $0 { return true } else { return false } }.count
        let failureCount = results.count - successCount
        
        print("✅ [ScholarDataService] 刷新完成: 成功 \(successCount), 失败 \(failureCount)")
        
        return results
    }
    
    /// 添加新学者并获取数据
    func addNewScholar(id: String) async throws -> Scholar {
        guard validateScholarId(id) else {
            throw ScholarDataError.invalidScholarId
        }
        
        // 检查是否已存在
        if dataManager.getScholar(id: id) != nil {
            throw ScholarDataError.invalidScholarId // 可以定义一个更具体的错误
        }
        
        // 获取并保存学者数据
        return try await fetchAndUpdateScholar(id: id)
    }
}
