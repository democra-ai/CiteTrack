import Foundation
import Combine

// MARK: - Scholar Publication Model
/// 学者的论文发表信息（用于获取引用数据）
public struct ScholarPublication: Identifiable, Codable {
    public let id: String
    public let title: String
    public let clusterId: String?
    public let citationCount: Int?
    public let year: Int?
    public let authors: [String]  // 作者列表（有序，从 Google Scholar 页面直接解析）

    init(title: String, clusterId: String?, citationCount: Int?, year: Int?, authors: [String] = []) {
        self.id = clusterId ?? UUID().uuidString
        self.title = title
        self.clusterId = clusterId
        self.citationCount = citationCount
        self.year = year
        self.authors = authors
    }

    // 向后兼容：旧缓存中没有 authors 字段时默认为空数组
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        clusterId = try container.decodeIfPresent(String.self, forKey: .clusterId)
        citationCount = try container.decodeIfPresent(Int.self, forKey: .citationCount)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
    }
}

// MARK: - Scholar Publications Result
/// 包含学者论文列表和学者基本信息的结果
public struct ScholarPublicationsResult {
    public let publications: [ScholarPublication]
    public let scholarInfo: ScholarFullInfo?  // 仅在第一页（startIndex == 0）时有值
    
    public init(publications: [ScholarPublication], scholarInfo: ScholarFullInfo? = nil) {
        self.publications = publications
        self.scholarInfo = scholarInfo
    }
}

// MARK: - Citation Fetch Service
public class CitationFetchService: ObservableObject {
    public static let shared = CitationFetchService()
    
    // URLSession配置
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.allowsCellularAccess = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // 速率限制配置
    private let rateLimitDelay: TimeInterval = 2.0  // 请求间隔2秒（减少延迟，首次请求无延迟）
    private var lastRequestTime: Date?
    private let requestQueue = DispatchQueue(label: "com.citetrack.citationfetch", qos: .userInitiated)
    
    // 随机延迟范围（增加不可预测性，但减少延迟）
    private func randomDelay() -> TimeInterval {
        return TimeInterval.random(in: 0.0...0.5)  // 减少随机延迟范围
    }
    
    private init() {}
    
    // MARK: - Error Types
    
    public enum CitationError: Error, LocalizedError {
        case invalidURL
        case networkError(Error)
        case parsingError(String)
        case noData
        case rateLimited
        case scholarNotFound
        case invalidScholarId
        case timeout
        case serverError(Int)
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "citation_error_invalid_url".localized
            case .networkError(let error):
                return String(format: "citation_error_network".localized, error.localizedDescription)
            case .parsingError(let details):
                return String(format: "citation_error_parsing".localized, details)
            case .noData:
                return "citation_error_no_data".localized
            case .rateLimited:
                return "citation_error_rate_limited".localized
            case .scholarNotFound:
                return "citation_error_scholar_not_found".localized
            case .invalidScholarId:
                return "citation_error_invalid_scholar_id".localized
            case .timeout:
                return "citation_error_timeout".localized
            case .serverError(let code):
                return String(format: "citation_error_server".localized, code)
            }
        }
        
        public var recoverySuggestion: String? {
            switch self {
            case .invalidURL:
                return "citation_recovery_invalid_url".localized
            case .networkError:
                return "citation_recovery_network".localized
            case .parsingError:
                return "citation_recovery_parsing".localized
            case .noData:
                return "citation_recovery_no_data".localized
            case .rateLimited:
                return "citation_recovery_rate_limited".localized
            case .scholarNotFound:
                return "citation_recovery_scholar_not_found".localized
            case .invalidScholarId:
                return "citation_recovery_invalid_scholar_id".localized
            case .timeout:
                return "citation_recovery_timeout".localized
            case .serverError:
                return "citation_recovery_server".localized
            }
        }
    }
    
    // MARK: - Logging
    
    private func logInfo(_ message: String) {
        print("ℹ️ [CitationFetch] \(message)")
    }
    
    private func logSuccess(_ message: String) {
        print("✅ [CitationFetch] \(message)")
    }
    
    private func logWarning(_ message: String) {
        // 警告信息仍然输出
        print("⚠️ [CitationFetch] \(message)")
    }
    
    private func logError(_ message: String, error: Error? = nil) {
        // 错误信息仍然输出
        if let error = error {
            print("❌ [CitationFetch] \(message): \(error.localizedDescription)")
        } else {
            print("❌ [CitationFetch] \(message)")
        }
    }
    
    private func logDebug(_ message: String) {
        #if DEBUG
        print("🔍 [CitationFetch] \(message)")
        #endif
    }
    
    // MARK: - Public Methods
    
    /// 抓取学者的所有引用论文
    public func fetchCitingPapers(
        for scholarId: String,
        completion: @escaping (Result<[CitingPaper], CitationError>) -> Void
    ) {
        guard !scholarId.isEmpty else {
            completion(.failure(.invalidScholarId))
            return
        }
        
        logInfo("Fetching citing papers for scholar: \(scholarId)")
        
        // 第一步：获取学者的所有论文
        fetchScholarPublications(for: scholarId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let publications):
                self.logInfo("Found \(publications.count) publications for scholar")
                
                if publications.isEmpty {
                    self.logWarning("No publications found for scholar: \(scholarId)")
                    completion(.success([]))
                    return
                }
                
                // 第二步：为每篇论文获取引用列表
                self.fetchCitingPapersForPublications(publications, scholarId: scholarId, completion: completion)
                
            case .failure(let error):
                self.logError("Failed to fetch scholar publications", error: error)
                completion(.failure(error))
            }
        }
    }
    
    /// 根据Cluster ID获取引用文章列表（公开方法）
    public func fetchCitingPapersForClusterId(
        _ clusterId: String,
        startIndex: Int = 0,
        sortByDate: Bool = true,
        completion: @escaping (Result<[CitingPaper], CitationError>) -> Void
    ) {
        applyRateLimit { [weak self] in
            guard let self = self else { return }
            
            // 构建引用页面URL（包含分页和排序参数）
            guard let url = self.buildCitedByURL(forClusterId: clusterId, startIndex: startIndex, sortByDate: sortByDate) else {
                completion(.failure(.invalidURL))
                return
            }
            
            self.logDebug("Fetching citing papers for cluster: \(clusterId)")
            self.logDebug("URL: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            self.configureRequest(&request)
            
            Self.urlSession.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.code == NSURLErrorTimedOut {
                            self.logError("Request timeout for cluster: \(clusterId)")
                            completion(.failure(.timeout))
                        } else {
                            self.logError("Network error for cluster: \(clusterId)", error: error)
                            completion(.failure(.networkError(error)))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.logError("No HTTP response for cluster: \(clusterId)")
                        completion(.failure(.noData))
                        return
                    }
                    
                    self.logDebug("HTTP Status: \(httpResponse.statusCode)")
                    
                    guard let data = data, let html = String(data: data, encoding: .utf8) else {
                        self.logError("Failed to decode HTML for cluster: \(clusterId)")
                        completion(.failure(.parsingError("Failed to decode HTML")))
                        return
                    }
                    
                    self.logDebug("Received HTML length: \(html.count)")
                    
                    // 检测是否被反爬虫拦截（CAPTCHA）
                    if html.contains("gs_captcha_ccl") || html.contains("recaptcha") || html.contains("Please show you're not a robot") {
                        self.logError("⚠️ CAPTCHA detected - Google Scholar requires verification")
                        completion(.failure(.parsingError("Google Scholar需要验证码验证。由于反爬虫限制，无法自动获取引用文章。\n\n建议：\n1. 等待几分钟后重试\n2. 在浏览器中手动访问该论文的引用页面\n3. 使用VPN切换网络")))
                        return
                    }
                    
                    // 解析引用论文
                    let papers = self.parseCitingPapersHTML(html, scholarId: "")
                    self.logSuccess("Parsed \(papers.count) citing papers for cluster \(clusterId)")
                    
                    completion(.success(papers))
                }
            }.resume()
        }
    }
    
    /// 获取学者的所有论文（公开方法）- 新版本，包含学者信息
    public func fetchScholarPublicationsWithInfo(
        for scholarId: String,
        sortBy: String? = nil,
        startIndex: Int = 0,
        forceRefresh: Bool = false,
        completion: @escaping (Result<ScholarPublicationsResult, CitationError>) -> Void
    ) {
        applyRateLimit { [weak self] in
            guard let self = self else { return }
            
            // 构建学者主页URL（包含排序和分页参数）
            guard let url = self.buildScholarProfileURL(for: scholarId, sortBy: sortBy, startIndex: startIndex) else {
                completion(.failure(.invalidURL))
                return
            }
            
            self.logInfo("Fetching scholar profile: \(scholarId)")
            self.logDebug("Request URL: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            self.configureRequest(&request)
            
            Self.urlSession.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.code == NSURLErrorTimedOut {
                            self.logError("Request timeout for scholar: \(scholarId)")
                            completion(.failure(.timeout))
                        } else {
                            self.logError("Network error for scholar: \(scholarId)", error: error)
                            completion(.failure(.networkError(error)))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.logError("No HTTP response received")
                        completion(.failure(.noData))
                        return
                    }
                    
                    self.logDebug("HTTP Status: \(httpResponse.statusCode)")
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        break
                    case 429:
                        self.logWarning("Rate limited by Google Scholar")
                        AnalyticsService.shared.logCitationError("rate_limit", statusCode: 429)
                        completion(.failure(.rateLimited))
                        return
                    case 404:
                        self.logError("Scholar not found: \(scholarId)")
                        AnalyticsService.shared.logCitationError("not_found", statusCode: 404)
                        completion(.failure(.scholarNotFound))
                        return
                    case 500...599:
                        self.logError("Server error: \(httpResponse.statusCode)")
                        AnalyticsService.shared.logCitationError("server_error", statusCode: httpResponse.statusCode)
                        completion(.failure(.serverError(httpResponse.statusCode)))
                        return
                    default:
                        self.logError("Unexpected HTTP status: \(httpResponse.statusCode)")
                        AnalyticsService.shared.logCitationError("http_error", statusCode: httpResponse.statusCode)
                        completion(.failure(.serverError(httpResponse.statusCode)))
                        return
                    }
                    
                    guard let data = data,
                          let htmlString = String(data: data, encoding: .utf8) else {
                        self.logError("Failed to decode HTML data")
                        completion(.failure(.noData))
                        return
                    }
                    
                    // 解析学者的论文列表
                    let publications = self.parseScholarPublications(from: htmlString)
                    
                    // 如果是第一页，同时提取学者完整信息
                    var scholarInfo: ScholarFullInfo? = nil
                    if startIndex == 0 {
                        scholarInfo = self.extractScholarFullInfo(from: htmlString)
                    }
                    
                    if publications.isEmpty {
                        self.logWarning("No publications found in scholar profile")
                    } else {
                        self.logSuccess("Parsed \(publications.count) publications")
                        if let info = scholarInfo {
                            self.logSuccess("Parsed scholar info: \(info.name), citations: \(info.totalCitations)")
                        }
                    }
                    
                    let result = ScholarPublicationsResult(
                        publications: publications,
                        scholarInfo: scholarInfo
                    )
                    completion(.success(result))
                }
            }.resume()
        }
    }
    
    /// 获取学者的所有论文（公开方法）- 旧版本，保持向后兼容
    public func fetchScholarPublications(
        for scholarId: String,
        sortBy: String? = nil,
        startIndex: Int = 0,
        forceRefresh: Bool = false,
        completion: @escaping (Result<[ScholarPublication], CitationError>) -> Void
    ) {
        // 调用新版本，然后只返回论文列表
        fetchScholarPublicationsWithInfo(
            for: scholarId,
            sortBy: sortBy,
            startIndex: startIndex,
            forceRefresh: forceRefresh
        ) { result in
            switch result {
            case .success(let publicationsResult):
                completion(.success(publicationsResult.publications))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 为多篇论文获取引用列表
    private func fetchCitingPapersForPublications(
        _ publications: [ScholarPublication],
        scholarId: String,
        completion: @escaping (Result<[CitingPaper], CitationError>) -> Void
    ) {
        var allCitingPapers: [CitingPaper] = []
        var processedCount = 0
        
        // 限制处理的论文数量，避免请求过多
        let limitedPublications = Array(publications.prefix(10))
        let actualTotal = limitedPublications.count
        
        guard !limitedPublications.isEmpty else {
            completion(.success([]))
                        return
                    }
                    
        logInfo("Fetching citations for \(actualTotal) publications...")
        
        for publication in limitedPublications {
            guard let clusterId = publication.clusterId else {
                logWarning("Skipping publication '\(publication.title.prefix(50))...' - no cluster ID")
                // 使用安全的加法，防止溢出
                processedCount = min(processedCount + 1, Int.max - 1)
                if processedCount == actualTotal {
                    logSuccess("Completed: found \(allCitingPapers.count) citing papers")
                    completion(.success(allCitingPapers))
                }
                continue
            }
            
            logDebug("Fetching citations for: '\(publication.title.prefix(50))...' (cluster: \(clusterId))")
            
            fetchCitingPapersForPublication(clusterId: clusterId, scholarId: scholarId) { [weak self] result in
                guard let self = self else { return }
                
                // 使用安全的加法，防止溢出
                processedCount = min(processedCount + 1, Int.max - 1)
                
                switch result {
                case .success(let papers):
                    allCitingPapers.append(contentsOf: papers)
                    self.logInfo("Progress: \(processedCount)/\(actualTotal) - Found \(papers.count) citations for publication")
                    
                case .failure(let error):
                    self.logWarning("Failed to fetch citations for publication: \(error.localizedDescription)")
                }
                
                // 所有论文处理完成
                if processedCount == actualTotal {
                    self.logSuccess("Completed: found \(allCitingPapers.count) total citing papers")
                    completion(.success(allCitingPapers))
                }
            }
        }
    }
    
    /// 为单篇论文获取引用列表
    private func fetchCitingPapersForPublication(
        clusterId: String,
        scholarId: String,
        completion: @escaping (Result<[CitingPaper], CitationError>) -> Void
    ) {
        applyRateLimit { [weak self] in
            guard let self = self else { return }
            
            guard let url = self.buildCitedByURL(forClusterId: clusterId, startIndex: 0, sortByDate: true) else {
                self.logError("Failed to build URL for cluster: \(clusterId)")
                completion(.failure(.invalidURL))
                return
            }
            
            self.logDebug("Fetching citations for cluster: \(clusterId)")
            self.logDebug("Request URL: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            self.configureRequest(&request)
            
            Self.urlSession.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.logError("Network error for cluster \(clusterId)", error: error)
                        completion(.failure(.networkError(error)))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.logError("No HTTP response for cluster \(clusterId)")
                        completion(.failure(.noData))
                        return
                    }
                    
                    self.logDebug("HTTP Status for cluster \(clusterId): \(httpResponse.statusCode)")
                    
                    guard httpResponse.statusCode == 200 else {
                        self.logWarning("Non-200 status (\(httpResponse.statusCode)) for cluster \(clusterId)")
                        completion(.success([]))
                        return
                    }
                    
                    guard let data = data,
                          let htmlString = String(data: data, encoding: .utf8) else {
                        self.logError("Failed to decode HTML for cluster \(clusterId)")
                        completion(.failure(.noData))
                        return
                    }
                    
                    self.logDebug("Received \(data.count) bytes for cluster \(clusterId)")
                    
                    let papers = self.parseCitingPapersHTML(htmlString, scholarId: scholarId)
                    self.logDebug("Parsed \(papers.count) citing papers for cluster \(clusterId)")
                    completion(.success(papers))
                }
            }.resume()
        }
    }
    
    /// 抓取引用作者信息
    public func fetchCitingAuthors(
        for scholarId: String,
        completion: @escaping (Result<[CitingAuthor], CitationError>) -> Void
    ) {
        // 首先获取引用论文列表
        fetchCitingPapers(for: scholarId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let papers):
                // 从论文中提取作者信息并聚合
                let authors = self.aggregateAuthorsFromPapers(papers)
                self.logSuccess("Aggregated \(authors.count) unique citing authors")
                completion(.success(authors))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// 从论文列表中聚合作者信息
    private func aggregateAuthorsFromPapers(_ papers: [CitingPaper]) -> [CitingAuthor] {
        var authorMap: [String: (name: String, papers: [CitingPaper])] = [:]
        
        // 聚合每个作者的论文
        for paper in papers {
            for authorName in paper.authors {
                let normalizedName = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedName.isEmpty || normalizedName == "Unknown Author" {
                    continue
                }
                
                // 使用作者名作为临时ID（实际应该从Google Scholar获取）
                let authorId = generateAuthorId(from: normalizedName)
                
                if var existing = authorMap[authorId] {
                    existing.papers.append(paper)
                    authorMap[authorId] = existing
                } else {
                    authorMap[authorId] = (name: normalizedName, papers: [paper])
                }
            }
        }
        
        // 转换为CitingAuthor对象
        let authors = authorMap.map { (id, data) -> CitingAuthor in
            let scholarUrl = "https://scholar.google.com/scholar?q=author:\"\(data.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? data.name)\""
            
            return CitingAuthor(
                id: id,
                name: data.name,
                affiliation: nil,  // 需要额外抓取
                interests: nil,    // 需要额外抓取
                citationCount: nil,  // 需要额外抓取
                hIndex: nil,       // 需要额外抓取
                citingPaperCount: data.papers.count,
                scholarUrl: scholarUrl
            )
        }
        
        // 按引用论文数量排序
        return authors.sorted { $0.citingPaperCount > $1.citingPaperCount }
    }
    
    /// 生成作者ID（基于名字的哈希）
    private func generateAuthorId(from name: String) -> String {
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "_")
        return "author_\(normalized.hashValue)"
    }
    
    /// 抓取作者的详细信息（从Google Scholar个人主页）
    public func fetchAuthorDetails(
        authorId: String,
        authorName: String,
        completion: @escaping (Result<CitingAuthor, CitationError>) -> Void
    ) {
        applyRateLimit { [weak self] in
            guard let self = self else { return }
            
            // 构建作者搜索URL
            guard let url = self.buildAuthorSearchURL(for: authorName) else {
                completion(.failure(.invalidURL))
                return
            }
            
            self.logInfo("Fetching author details: \(authorName)")
            self.logDebug("Request URL: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            self.configureRequest(&request)
            
            Self.urlSession.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.code == NSURLErrorTimedOut {
                            self.logError("Request timeout for author: \(authorName)")
                            completion(.failure(.timeout))
                        } else {
                            self.logError("Network error for author: \(authorName)", error: error)
                            completion(.failure(.networkError(error)))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.logError("No HTTP response received")
                        completion(.failure(.noData))
                        return
                    }
                    
                    self.logDebug("HTTP Status: \(httpResponse.statusCode)")
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        break
                    case 429:
                        self.logWarning("Rate limited by Google Scholar")
                        completion(.failure(.rateLimited))
                        return
                    case 404:
                        self.logWarning("Author not found: \(authorName)")
                        // 返回基本信息而不是失败
                        let basicAuthor = CitingAuthor(
                            id: authorId,
                            name: authorName,
                            citingPaperCount: 0,
                            scholarUrl: url.absoluteString
                        )
                        completion(.success(basicAuthor))
                        return
                    case 500...599:
                        self.logError("Server error: \(httpResponse.statusCode)")
                        completion(.failure(.serverError(httpResponse.statusCode)))
                        return
                    default:
                        self.logError("Unexpected HTTP status: \(httpResponse.statusCode)")
                        completion(.failure(.serverError(httpResponse.statusCode)))
                        return
                    }
                    
                    guard let data = data,
                          let htmlString = String(data: data, encoding: .utf8) else {
                        self.logError("Failed to decode HTML data")
                        completion(.failure(.noData))
                        return
                    }
                    
                    if let author = self.parseAuthorDetailsHTML(htmlString, authorId: authorId, authorName: authorName) {
                        self.logSuccess("Successfully parsed author details")
                        completion(.success(author))
                    } else {
                        self.logWarning("Failed to parse author details, returning basic info")
                        // 如果解析失败，返回基本信息
                        let basicAuthor = CitingAuthor(
                            id: authorId,
                            name: authorName,
                            citingPaperCount: 0,
                            scholarUrl: url.absoluteString
                        )
                        completion(.success(basicAuthor))
                    }
                }
            }.resume()
        }
    }
    
    /// 构建作者搜索URL
    private func buildAuthorSearchURL(for authorName: String) -> URL? {
        let encodedName = authorName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? authorName
        let urlString = "https://scholar.google.com/citations?hl=en&view_op=search_authors&mauthors=\(encodedName)"
        return URL(string: urlString)
    }
    
    /// 解析作者详情HTML
    private func parseAuthorDetailsHTML(_ html: String, authorId: String, authorName: String) -> CitingAuthor? {
        // 提取机构
        let affiliation = extractAuthorAffiliation(from: html)
        
        // 提取研究兴趣
        let interests = extractAuthorInterests(from: html)
        
        // 提取引用数
        let citationCount = extractAuthorCitationCount(from: html)
        
        // 提取h-index
        let hIndex = extractAuthorHIndex(from: html)
        
        // 提取Scholar URL
        let scholarUrl = extractAuthorScholarUrl(from: html) ?? "https://scholar.google.com/scholar?q=author:\"\(authorName)\""
        
        return CitingAuthor(
            id: authorId,
            name: authorName,
            affiliation: affiliation,
            interests: interests,
            citationCount: citationCount,
            hIndex: hIndex,
            citingPaperCount: 0,  // 这个值应该从聚合数据中获取
            scholarUrl: scholarUrl
        )
    }
    
    /// 提取作者机构
    private func extractAuthorAffiliation(from html: String) -> String? {
        let patterns = [
            #"<div class="gs_ai_aff">(.*?)</div>"#,
            #"<div class="gsc_prf_il">(.*?)</div>"#
        ]
        
        for pattern in patterns {
            if let affiliation = extractFirstMatch(from: html, pattern: pattern) {
                let cleaned = cleanHTML(affiliation)
                return cleaned.isEmpty ? nil : cleaned
            }
        }
        
        return nil
    }
    
    /// 提取作者研究兴趣
    private func extractAuthorInterests(from html: String) -> [String]? {
        let patterns = [
            #"<div class="gs_ai_int">(.*?)</div>"#,
            #"<div class="gsc_prf_int">(.*?)</div>"#
        ]
        
        for pattern in patterns {
            if let interestsString = extractFirstMatch(from: html, pattern: pattern) {
                let cleaned = cleanHTML(interestsString)
                let interests = cleaned.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                if !interests.isEmpty {
                    return interests
                }
            }
        }
        
        return nil
    }
    
    /// 提取作者总引用数
    private func extractAuthorCitationCount(from html: String) -> Int? {
        let patterns = [
            #"<td class="gsc_rsb_std">(\d+)</td>"#,
            #"Citations</a></td><td class="gsc_rsb_std">(\d+)</td>"#
        ]
        
        for pattern in patterns {
            if let countString = extractFirstMatch(from: html, pattern: pattern),
               let count = Int(countString) {
                return count
            }
        }
        
        return nil
    }
    
    /// 提取作者h-index
    private func extractAuthorHIndex(from html: String) -> Int? {
        let patterns = [
            #"h-index</a></td><td class="gsc_rsb_std">(\d+)</td>"#,
            #"<td>h-index</td><td[^>]*>(\d+)</td>"#
        ]
        
        for pattern in patterns {
            if let hString = extractFirstMatch(from: html, pattern: pattern),
               let h = Int(hString) {
                return h
            }
        }
        
        return nil
    }
    
    /// 提取作者Scholar URL
    private func extractAuthorScholarUrl(from html: String) -> String? {
        let pattern = #"<a[^>]*href="/citations\?user=([^"&]+)"#
        
        if let userId = extractFirstMatch(from: html, pattern: pattern) {
            return "https://scholar.google.com/citations?user=\(userId)"
        }
        
        return nil
    }
    
    /// 抓取单篇论文的详细信息
    public func fetchPaperDetails(
        paperId: String,
        completion: @escaping (Result<CitingPaper, CitationError>) -> Void
    ) {
        guard !paperId.isEmpty else {
            completion(.failure(.invalidURL))
            return
        }
        
        applyRateLimit { [weak self] in
            guard let self = self else { return }
            
            guard let url = self.buildPaperDetailURL(for: paperId) else {
                completion(.failure(.invalidURL))
                return
            }
            
            self.logInfo("Fetching paper details: \(paperId)")
            self.logDebug("Request URL: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            self.configureRequest(&request)
            
            Self.urlSession.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.code == NSURLErrorTimedOut {
                            self.logError("Request timeout for paper: \(paperId)")
                            completion(.failure(.timeout))
                        } else {
                            self.logError("Network error for paper: \(paperId)", error: error)
                            completion(.failure(.networkError(error)))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.logError("No HTTP response received")
                        completion(.failure(.noData))
                        return
                    }
                    
                    self.logDebug("HTTP Status: \(httpResponse.statusCode)")
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        break
                    case 429:
                        self.logWarning("Rate limited by Google Scholar")
                        completion(.failure(.rateLimited))
                        return
                    case 404:
                        self.logError("Paper not found: \(paperId)")
                        completion(.failure(.scholarNotFound))
                        return
                    case 500...599:
                        self.logError("Server error: \(httpResponse.statusCode)")
                        completion(.failure(.serverError(httpResponse.statusCode)))
                        return
                    default:
                        self.logError("Unexpected HTTP status: \(httpResponse.statusCode)")
                        completion(.failure(.serverError(httpResponse.statusCode)))
                        return
                    }
                    
                    guard let data = data,
                          let htmlString = String(data: data, encoding: .utf8) else {
                        self.logError("Failed to decode HTML data")
                        completion(.failure(.noData))
                        return
                    }
                    
                    if let paper = self.parsePaperDetailsHTML(htmlString, paperId: paperId) {
                        self.logSuccess("Successfully parsed paper details")
                        completion(.success(paper))
                    } else {
                        self.logError("Failed to parse paper details")
                        completion(.failure(.parsingError("Failed to extract paper information")))
                    }
                }
            }.resume()
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// 应用速率限制
    /// 注意：首次请求（lastRequestTime == nil）不延迟，立即执行
    private func applyRateLimit(completion: @escaping () -> Void) {
        requestQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 如果是首次请求，立即执行，不延迟
            guard let lastTime = self.lastRequestTime else {
                self.lastRequestTime = Date()
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            
            // 非首次请求：检查是否需要延迟
            let elapsed = Date().timeIntervalSince(lastTime)
            let totalDelay = self.rateLimitDelay + self.randomDelay()
            if elapsed < totalDelay {
                let delay = totalDelay - elapsed
                self.logDebug("Rate limiting: waiting \(String(format: "%.2f", delay))s (elapsed: \(String(format: "%.2f", elapsed))s)")
                // Use non-blocking delay instead of Thread.sleep to avoid freezing
                self.lastRequestTime = Date().addingTimeInterval(delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    completion()
                }
            } else {
                self.logDebug("No rate limit delay needed (elapsed: \(String(format: "%.2f", elapsed))s)")
                self.lastRequestTime = Date()
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    
    /// 配置HTTP请求头
    private func configureRequest(_ request: inout URLRequest) {
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    }
    
    /// 构建学者主页URL
    private func buildScholarProfileURL(for scholarId: String, sortBy: String? = nil, startIndex: Int = 0) -> URL? {
        var urlString = "https://scholar.google.com/citations?user=\(scholarId)&hl=en&cstart=\(startIndex)&pagesize=100"
        
        // 添加排序参数（如果提供）
        if let sortBy = sortBy {
            urlString += "&sortby=\(sortBy)"
        }
        
        return URL(string: urlString)
    }
    
    /// 构建引用页面URL（使用论文cluster ID）
    private func buildCitedByURL(forClusterId clusterId: String, startIndex: Int = 0, sortByDate: Bool = true) -> URL? {
        // Google Scholar的"Cited by"页面URL格式，支持分页和排序参数
        // scisbd=1 表示按日期排序，不设置表示按相关性排序
        var urlString = "https://scholar.google.com/scholar?hl=en&cites=\(clusterId)"
        if sortByDate {
            urlString += "&scisbd=1"
        }
        if startIndex > 0 {
            urlString += "&start=\(startIndex)"
        }
        return URL(string: urlString)
    }
    
    /// 构建论文详情URL
    private func buildPaperDetailURL(for paperId: String) -> URL? {
        let urlString = "https://scholar.google.com/scholar?hl=en&cluster=\(paperId)"
        return URL(string: urlString)
    }
    
    /// 解析学者的论文列表
    public func parseScholarPublications(from html: String) -> [ScholarPublication] {
        var publications: [ScholarPublication] = []
        
        // Google Scholar学者主页的论文列表结构：
        // <tr class="gsc_a_tr">...</tr>
        let pattern = #"<tr class="gsc_a_tr">(.*?)</tr>"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            logError("Failed to create publications regex")
            return publications
        }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        logDebug("Found \(matches.count) potential publication entries")
        
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            
            let entryRange = match.range(at: 1)
            let entryHTML = nsString.substring(with: entryRange)
            
            if let publication = parseSinglePublication(from: entryHTML) {
                publications.append(publication)
            }
        }
        
        return publications
    }
    
    /// 解析单篇论文信息
    private func parseSinglePublication(from html: String) -> ScholarPublication? {
        // 提取标题
        let titlePattern = #"<a[^>]*class="gsc_a_at"[^>]*>(.*?)</a>"#
        guard let title = extractFirstMatch(from: html, pattern: titlePattern) else {
            logDebug("Failed to extract title from publication HTML")
            return nil
        }
        let cleanTitle = cleanHTML(title)
        
        // 从"Cited by"链接提取cites参数（可能包含多个ID）
        var clusterId: String?
        
        // 输出HTML片段用于调试（仅特定论文）
        if cleanTitle.contains("Generative") {
            logDebug("=== HTML SNIPPET ===")
            logDebug(String(html.prefix(500)))
            logDebug("=== END ===")
        }
        
        // 尝试多种正则模式来提取cites参数
        // 注意: HTML中 & 被编码为 &amp;
        let citesPatterns = [
            // 模式1: 匹配 &amp;cites=
            #"&amp;cites=([0-9,]+)"#,
            // 模式2: 直接查找cites=后面的数字（如果HTML已解码）
            #"[&?]cites=([0-9,]+)"#,
            // 模式3: 完整href匹配
            #"href="https://scholar\.google\.com/scholar\?[^"]*&amp;cites=([0-9,]+)"#,
        ]
        
        for (index, pattern) in citesPatterns.enumerated() {
            if let cites = extractFirstMatch(from: html, pattern: pattern) {
                let firstId = cites.components(separatedBy: ",").first ?? cites
                clusterId = firstId
                logDebug("✓ Found cluster ID via pattern \(index + 1): \(firstId)")
                break
            }
        }
        
        // 提取引用数
        let citationPattern = #"<a[^>]*class="gsc_a_ac[^"]*"[^>]*>(\d+)</a>"#
        let citationCountStr = extractFirstMatch(from: html, pattern: citationPattern)
        let citationCount = citationCountStr.flatMap { Int($0) }
        
        // 提取年份
        let yearPattern = #"<span class="gsc_a_h[^"]*">(\d{4})</span>"#
        let yearStr = extractFirstMatch(from: html, pattern: yearPattern)
        let year = yearStr.flatMap { Int($0) }

        // 提取作者列表（从 gs_gray div 中解析，格式："Author1, Author2, ..."）
        var authors: [String] = []

        // Strategy 1: gs_gray div (GS profile page) — flexible class matching
        // Handles class="gs_gray", class="gs_gray ", class="gs_gray gs_xxx", extra attributes
        let authorPatterns = [
            #"<div[^>]*class\s*=\s*"gs_gray[^"]*"[^>]*>(.*?)</div>"#,
            #"<div[^>]*class\s*=\s*"gs_a[^"]*"[^>]*>(.*?)</div>"#,
        ]
        for ap in authorPatterns {
            if let raw = extractFirstMatch(from: html, pattern: ap) {
                // 取第一个 " - " 之前的部分（作者部分）
                let parts = raw.components(separatedBy: " - ")
                if let authorPart = parts.first {
                    let cleaned = cleanHTML(authorPart)
                    let parsed = cleaned.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0 != "…" && $0 != "..." }
                    if !parsed.isEmpty {
                        authors = parsed
                        break
                    }
                }
            }
        }

        // Strategy 2: fallback — find the first <div> after the title </a> tag
        // On some GS pages, the class names might differ
        if authors.isEmpty {
            let fallbackPattern = #"class="gsc_a_at"[^>]*>.*?</a>\s*<div[^>]*>(.*?)</div>"#
            if let raw = extractFirstMatch(from: html, pattern: fallbackPattern) {
                let cleaned = cleanHTML(raw)
                // Verify it looks like author names (has commas, not a venue/DOI)
                let lower = cleaned.lowercased()
                if !lower.contains("vol.") && !lower.contains("doi:") && !lower.contains("isbn")
                    && !lower.contains("http") && cleaned.count < 500 {
                    let parsed = cleaned.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0 != "…" && $0 != "..." }
                    if !parsed.isEmpty {
                        authors = parsed
                    }
                }
            }
        }

        if authors.isEmpty {
            logDebug("⚠️ No authors extracted for '\(cleanTitle.prefix(50))...'")
        }

        let publication = ScholarPublication(
            title: cleanTitle,
            clusterId: clusterId,
            citationCount: citationCount,
            year: year,
            authors: authors
        )
        
        if clusterId == nil && (citationCount ?? 0) > 0 {
            logWarning("✗ No cluster ID found for '\(cleanTitle.prefix(50))...' (\(citationCount ?? 0) cites)")
        }
        
        return publication
    }
    
    /// 解析引用论文列表HTML
    func parseCitingPapersHTML(_ html: String, scholarId: String) -> [CitingPaper] {
        var papers: [CitingPaper] = []
        
        // 输出HTML片段用于调试
        logDebug("=== CITING PAPERS HTML SNIPPET (first 800 chars) ===")
        logDebug(String(html.prefix(800)))
        logDebug("=== END SNIPPET ===")
        
        // Google Scholar搜索结果的基本结构：
        // <div class="gs_r gs_or gs_scl">...</div>
        // Use lookahead to capture entire result block (old pattern was too restrictive,
        // missing gs_a div with author info)
        let resultPattern = #"<div class="gs_r gs_or gs_scl"[^>]*>([\s\S]*?)(?=<div class="gs_r gs_or gs_scl"|<div id="gs_res_ccl_bot"|\z)"#
        
        guard let resultRegex = try? NSRegularExpression(pattern: resultPattern, options: [.dotMatchesLineSeparators]) else {
            logError("Failed to create result regex")
            return papers
        }
        
        let nsString = html as NSString
        let matches = resultRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        logDebug("Found \(matches.count) potential paper entries")
        
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            
            let resultRange = match.range(at: 1)
            let resultHTML = nsString.substring(with: resultRange)
            
            if let paper = parseSinglePaperResult(resultHTML, citedScholarId: scholarId) {
                papers.append(paper)
            }
        }
        
        return papers
    }
    
    /// 解析单个论文结果
    private func parseSinglePaperResult(_ html: String, citedScholarId: String) -> CitingPaper? {
        // 提取论文ID（从cluster参数）
        let paperId = extractPaperId(from: html) ?? UUID().uuidString
        
        // 提取标题
        guard let title = extractTitle(from: html), !title.isEmpty else {
            return nil
        }
        
        // 提取作者
        let authors = extractAuthors(from: html)
        
        // 提取年份
        let year = extractYear(from: html)
        
        // 提取发表场所
        let venue = extractVenue(from: html)
        
        // 提取引用数
        let citationCount = extractCitationCount(from: html)
        
        // 提取摘要
        let abstract = extractAbstract(from: html)
        
        // 提取链接
        let scholarUrl = extractScholarUrl(from: html, paperId: paperId)
        let pdfUrl = extractPdfUrl(from: html)
        
        return CitingPaper(
            id: paperId,
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            citationCount: citationCount,
            abstract: abstract,
            scholarUrl: scholarUrl,
            pdfUrl: pdfUrl,
            citedScholarId: citedScholarId,
            fetchedAt: Date()
        )
    }
    
    /// 解析论文详情HTML
    func parsePaperDetailsHTML(_ html: String, paperId: String) -> CitingPaper? {
        // 提取标题
        guard let title = extractTitle(from: html), !title.isEmpty else {
            return nil
        }
        
        // 提取作者
        let authors = extractAuthors(from: html)
        
        // 提取年份
        let year = extractYear(from: html)
        
        // 提取发表场所
        let venue = extractVenue(from: html)
        
        // 提取引用数
        let citationCount = extractCitationCount(from: html)
        
        // 提取摘要
        let abstract = extractAbstract(from: html)
        
        // 提取链接
        let scholarUrl = extractScholarUrl(from: html, paperId: paperId)
        let pdfUrl = extractPdfUrl(from: html)
        
        return CitingPaper(
            id: paperId,
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            citationCount: citationCount,
            abstract: abstract,
            scholarUrl: scholarUrl,
            pdfUrl: pdfUrl,
            citedScholarId: "",  // 详情页不需要citedScholarId
            fetchedAt: Date()
        )
    }
    
    // MARK: - HTML Parsing Helpers
    
    /// 提取论文ID
    private func extractPaperId(from html: String) -> String? {
        let patterns = [
            #"cluster=(\d+)"#,
            #"cites=(\d+)"#
        ]
        
        for pattern in patterns {
            if let id = extractFirstMatch(from: html, pattern: pattern) {
                return id
            }
        }
        
        return nil
    }
    
    /// 提取标题
    private func extractTitle(from html: String) -> String? {
        let patterns = [
            #"<h3[^>]*class="gs_rt"[^>]*>(?:<a[^>]*>)?(.*?)(?:</a>)?</h3>"#,
            #"<h3[^>]*>(?:<a[^>]*>)?(.*?)(?:</a>)?</h3>"#,
            #"<a[^>]*class="gs_rt"[^>]*>(.*?)</a>"#
        ]
        
        for pattern in patterns {
            if let title = extractFirstMatch(from: html, pattern: pattern) {
                return cleanHTML(title)
            }
        }
        
        return nil
    }
    
    /// 提取作者
    private func extractAuthors(from html: String) -> [String] {
        let patterns = [
            #"<div class="gs_a">(.*?)</div>"#,
            #"<div class="gs_gray">(.*?)</div>"#
        ]
        
        for pattern in patterns {
            if let authorsString = extractFirstMatch(from: html, pattern: pattern) {
                // 作者通常在第一个"-"之前
                let components = authorsString.components(separatedBy: " - ")
                if let authorsPart = components.first {
                    let cleanedAuthors = cleanHTML(authorsPart)
                    // 分割作者名（通常用逗号分隔）
                    let authors = cleanedAuthors.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    if !authors.isEmpty {
                        return authors
                    }
                }
            }
        }
        
        return ["Unknown Author"]
    }
    
    /// 提取年份
    private func extractYear(from html: String) -> Int? {
        // 优先从 gs_a div 中提取年份（这是作者和发表信息区域）
        // 格式：<div class="gs_a">作者 - 期刊, 2025 - 网站</div>
        let gsAPattern = #"<div class="gs_a">(.*?)</div>"#
        if let gsAContent = extractFirstMatch(from: html, pattern: gsAPattern) {
            // 在 gs_a 内容中查找年份，通常在最后一个 " - " 之前
            // 格式通常是：作者 - 期刊, 年份 - 网站
            let components = gsAContent.components(separatedBy: " - ")
            if components.count >= 2 {
                // 在倒数第二个部分中查找年份（通常是"期刊, 年份"）
                let venuePart = components[components.count - 2]
                // 查找4位数字的年份（1900-2099），优先匹配最近的年份
                let yearPattern = #"\b(19\d{2}|20\d{2})\b"#
                guard let regex = try? NSRegularExpression(pattern: yearPattern, options: []) else {
                    return nil
                }
                
                let nsString = venuePart as NSString
                let matches = regex.matches(in: venuePart, options: [], range: NSRange(location: 0, length: nsString.length))
                
                // 优先选择最近的年份（2020-2099）
                var foundYear: Int? = nil
                for match in matches.reversed() { // 从后往前查找，通常年份在最后
                    let yearRange = match.range(at: 1)
                    let yearString = nsString.substring(with: yearRange)
                    if let year = Int(yearString) {
                        if year >= 2020 {
                            return year  // 直接返回最近的年份
                        } else if foundYear == nil {
                            foundYear = year  // 保存第一个找到的年份作为备选
                        }
                    }
                }
                
                if let year = foundYear {
            return year
        }
            }
        }
        
        // 如果从 gs_a 中没找到，尝试在整个HTML中查找，但排除URL参数
        // 排除常见的URL参数模式
        let excludedPatterns = [
            #"as_sdt=\d{4}"#,
            #"as_ylo=\d{4}"#,
            #"as_yhi=\d{4}"#,
            #"scisbd=\d+"#,
            #"hl=\w+"#  // 避免匹配到其他参数
        ]
        
        // 查找所有年份
        let yearPattern = #"\b(19\d{2}|20\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: yearPattern, options: []) else {
        return nil
        }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 找到所有年份，排除URL参数中的年份，优先选择最近的年份
        var candidateYears: [Int] = []
        for match in matches {
            let yearRange = match.range(at: 1)
            let yearString = nsString.substring(with: yearRange)
            
            // 检查这个年份是否在URL参数中
            let contextStart = max(0, yearRange.location - 30)
            let contextLength = min(nsString.length - contextStart, yearRange.length + 60)
            let contextRange = NSRange(location: contextStart, length: contextLength)
            let context = nsString.substring(with: contextRange)
            
            var isInURL = false
            for excludedPattern in excludedPatterns {
                if let _ = try? NSRegularExpression(pattern: excludedPattern, options: []).firstMatch(in: context, options: [], range: NSRange(location: 0, length: context.count)) {
                    isInURL = true
                    break
                }
            }
            
            if !isInURL, let year = Int(yearString), year >= 1900 && year <= 2099 {
                candidateYears.append(year)
            }
        }
        
        // 优先返回最近的年份（2020-2099）
        if let recentYear = candidateYears.filter({ $0 >= 2020 }).max() {
            return recentYear
        }
        
        // 如果没有2020年以后的年份，返回最大的年份
        return candidateYears.max()
    }
    
    /// 提取发表场所
    private func extractVenue(from html: String) -> String? {
        let pattern = #"<div class="gs_a">(.*?)</div>"#
        
        if let metaString = extractFirstMatch(from: html, pattern: pattern) {
            let components = metaString.components(separatedBy: " - ")
            // 发表场所通常在第二个部分
            if components.count >= 2 {
                let venue = cleanHTML(components[1])
                return venue.isEmpty ? nil : venue
            }
        }
        
        return nil
    }
    
    /// 提取引用数
    private func extractCitationCount(from html: String) -> Int? {
        let patterns = [
            #"Cited by (\d+)"#,
            #"被引用次数[：:]\s*(\d+)"#
        ]
        
        for pattern in patterns {
            if let countString = extractFirstMatch(from: html, pattern: pattern),
               let count = Int(countString) {
                return count
            }
        }
        
        return nil
    }
    
    /// 提取摘要
    private func extractAbstract(from html: String) -> String? {
        let patterns = [
            #"<div class="gs_rs">(.*?)</div>"#,
            #"<span class="gs_rs">(.*?)</span>"#
        ]
        
        for pattern in patterns {
            if let abstract = extractFirstMatch(from: html, pattern: pattern) {
                let cleaned = cleanHTML(abstract)
                return cleaned.isEmpty ? nil : cleaned
            }
        }
        
        return nil
    }
    
    /// 提取Google Scholar链接
    private func extractScholarUrl(from html: String, paperId: String) -> String? {
        let pattern = #"<a[^>]*href="(/scholar\?[^"]*)"#
        
        if let path = extractFirstMatch(from: html, pattern: pattern) {
            return "https://scholar.google.com" + path
        }
        
        // 如果没有找到，使用paperId构建
        if !paperId.isEmpty {
            return "https://scholar.google.com/scholar?cluster=\(paperId)"
        }
        
        return nil
    }
    
    /// 提取PDF链接
    private func extractPdfUrl(from html: String) -> String? {
        let patterns = [
            #"<a[^>]*href="([^"]*\.pdf)"#,
            #"<div class="gs_or_ggsm"><a[^>]*href="([^"]*)"#
        ]
        
        for pattern in patterns {
            if let url = extractFirstMatch(from: html, pattern: pattern) {
                // 确保是完整的URL
                if url.hasPrefix("http") {
                    return url
                }
            }
        }
        
        return nil
    }
    
    /// 提取正则表达式的第一个匹配
    internal func extractFirstMatch(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let matchRange = match.range(at: 1)
        return nsString.substring(with: matchRange)
    }
    
    /// 清理HTML标签和实体
    private func cleanHTML(_ html: String) -> String {
        var cleaned = html
        
        // 移除HTML标签
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // 解码HTML实体
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&apos;", with: "'")
        
        // 移除多余的空白
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
}

// MARK: - Combine Support
public extension CitationFetchService {
    /// 使用Combine抓取引用论文
    func fetchCitingPapersPublisher(for scholarId: String) -> AnyPublisher<[CitingPaper], CitationError> {
        return Future { promise in
            self.fetchCitingPapers(for: scholarId) { result in
                promise(result)
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// 使用Combine抓取论文详情
    func fetchPaperDetailsPublisher(paperId: String) -> AnyPublisher<CitingPaper, CitationError> {
        return Future { promise in
            self.fetchPaperDetails(paperId: paperId) { result in
                promise(result)
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// 使用Combine抓取引用作者
    func fetchCitingAuthorsPublisher(for scholarId: String) -> AnyPublisher<[CitingAuthor], CitationError> {
        return Future { promise in
            self.fetchCitingAuthors(for: scholarId) { result in
                promise(result)
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// 使用Combine抓取作者详情
    func fetchAuthorDetailsPublisher(authorId: String, authorName: String) -> AnyPublisher<CitingAuthor, CitationError> {
        return Future { promise in
            self.fetchAuthorDetails(authorId: authorId, authorName: authorName) { result in
                promise(result)
            }
        }
        .eraseToAnyPublisher()
    }
}
