import Foundation
import Combine

// MARK: - Google Scholar Service
public class GoogleScholarService: ObservableObject {
    public static let shared = GoogleScholarService()
    
    // 共享的URLSession配置，包含合理的超时设置
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0  // 单个请求超时30秒
        config.timeoutIntervalForResource = 60.0  // 总资源获取超时60秒
        config.allowsCellularAccess = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // 总是获取最新数据
        return URLSession(configuration: config)
    }()
    
    public init() {}
    
    // MARK: - Error Types
    public enum ScholarError: Error, LocalizedError {
        case invalidURL
        case noData
        case parsingError
        case networkError(Error)
        case rateLimited
        case scholarNotFound
        case invalidScholarId
        
        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "invalid_url".localized
            case .noData:
                return "no_data_returned".localized
            case .parsingError:
                return "parsing_error".localized
            case .networkError(let error):
                return String(format: "network_error".localized, error.localizedDescription)
            case .rateLimited:
                return "rate_limited_error".localized
            case .scholarNotFound:
                return "scholar_not_found".localized
            case .invalidScholarId:
                return "invalid_scholar_id".localized
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Extract scholar ID from Google Scholar URL
    public func extractScholarId(from urlString: String) -> String? {
        // 清理URL字符串，移除多余的空格
        let cleanedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 检查是否已经是纯ID（不包含URL）
        if !cleanedUrl.contains("scholar.google.com") && !cleanedUrl.contains("http") {
            return cleanedUrl
        }
        
        // 尝试从URL中提取学者ID
        let patterns = [
            #"scholar\.google\.com/citations\?user=([^&]+)"#,
            #"scholar\.google\.com/citations\?user=([^&]+)&"#,
            #"user=([^&]+)"#
        ]
        
        for pattern in patterns {
            if let scholarId = extractFirstMatch(from: cleanedUrl, pattern: pattern) {
                return scholarId
            }
        }
        
        return nil
    }
    
    /// Fetch scholar information (name and citations)
    public func fetchScholarInfo(for scholarId: String, completion: @escaping (Result<(name: String, citations: Int), ScholarError>) -> Void) {
        guard !scholarId.isEmpty else {
            completion(.failure(.invalidScholarId))
            return
        }
        
        guard let url = URL(string: "https://scholar.google.com/citations?user=\(scholarId)&hl=en") else {
            completion(.failure(.invalidURL))
            return
        }
        
        print("📡 开始获取学者信息: \(scholarId)")
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        Self.urlSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 网络请求失败: \(error.localizedDescription)")
                    completion(.failure(.networkError(error)))
                    return
                }
                
                guard let data = data else {
                    print("❌ 没有接收到数据")
                    completion(.failure(.noData))
                    return
                }
                
                // 检查HTTP状态码
                if let httpResponse = response as? HTTPURLResponse {
                    print("📊 HTTP状态码: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 429 {
                        completion(.failure(.rateLimited))
                        return
                    }
                    
                    if httpResponse.statusCode >= 400 {
                        completion(.failure(.scholarNotFound))
                        return
                    }
                }
                
                let htmlString = String(data: data, encoding: .utf8) ?? ""

                // A blocked / CAPTCHA / consent / "unusual traffic" page comes back with
                // HTTP 200 but is NOT a real profile. Never parse it as success — that was
                // letting a garbage/zero value overwrite the correct citation count.
                if self.isBlockedPage(htmlString) {
                    print("⛔️ 被 Google Scholar 拦截（验证/限流页），放弃本次更新")
                    completion(.failure(.rateLimited))
                    return
                }

                // 解析学者姓名和引用数
                let name = self.extractScholarName(from: htmlString)
                guard !name.isEmpty else {
                    print("❌ 未能解析到学者姓名")
                    completion(.failure(.scholarNotFound))
                    return
                }
                // Fail instead of returning 0 when the real citations cell is missing:
                // a partial/interstitial page must never overwrite a good value.
                guard let citations = self.extractCitationCount(from: htmlString) else {
                    print("❌ 未能解析到引用数（页面异常），放弃本次更新")
                    completion(.failure(.parsingError))
                    return
                }

                print("✅ 成功获取学者信息: \(name), 引用数: \(citations)")
                
                // 同时解析论文列表并保存到统一缓存（最大化利用页面内容）
                Task { @MainActor in
                    // 使用 CitationFetchService 解析论文列表
                    let publications = CitationFetchService.shared.parseScholarPublications(from: htmlString)
                    
                    // 提取完整的学者信息（h-index, i10-index）
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
                            sortBy: "total",  // 默认使用 total 排序
                            startIndex: 0,
                            source: .dashboard
                        )
                        UnifiedCacheManager.shared.saveDataSnapshot(snapshot)
                        print("📦 [GoogleScholarService] Saved \(publications.count) publications to unified cache from scholar page refresh")
                    }
                }
                
                completion(.success((name: name, citations: citations)))
            }
        }.resume()
    }
    
    /// Fetch citation count only
    public func fetchCitationCount(for scholarId: String, completion: @escaping (Result<Int, ScholarError>) -> Void) {
        fetchScholarInfo(for: scholarId) { result in
            switch result {
            case .success(let info):
                completion(.success(info.citations))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Combine Support
    
    public func fetchScholarInfoPublisher(for scholarId: String) -> AnyPublisher<(name: String, citations: Int), ScholarError> {
        return Future { promise in
            self.fetchScholarInfo(for: scholarId) { result in
                promise(result)
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func fetchCitationCountPublisher(for scholarId: String) -> AnyPublisher<Int, ScholarError> {
        return fetchScholarInfoPublisher(for: scholarId)
            .map { $0.citations }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Parsing Methods
    
    /// Detects a Google Scholar CAPTCHA / consent / "unusual traffic" interstitial,
    /// which is served with HTTP 200 and must NOT be parsed as a real profile.
    private func isBlockedPage(_ html: String) -> Bool {
        if html.isEmpty { return true }
        let lower = html.lowercased()
        // A genuine profile page always carries BOTH the name element and the stats
        // table. If both are present it is real — even if a paper title happens to
        // contain "captcha"/"recaptcha"/"unusual traffic" (checking needles first would
        // wrongly flag such profiles and silently stop them from ever updating).
        if lower.contains("gsc_prf_in") && lower.contains("gsc_rsb_std") { return false }
        // Otherwise: a CAPTCHA / consent / "sorry" interstitial, or simply not a profile.
        let needles = ["gs_captcha", "g-recaptcha", "/sorry/", "captcha-form"]
        for n in needles where lower.contains(n) { return true }
        if !lower.contains("gsc_prf_in") && !lower.contains("gsc_rsb_std") { return true }
        return false
    }

    private func extractScholarName(from html: String) -> String {
        // Only the real profile-name element. A generic <h3> fallback used to match
        // headings on consent / "unusual traffic" pages, making a blocked fetch look
        // like a success — removed on purpose.
        let patterns = [
            #"<div id="gsc_prf_in">([^<]+)</div>"#,
            #"<div[^>]*class="gsc_prf_in"[^>]*>([^<]+)</div>"#
        ]

        for pattern in patterns {
            if let name = extractFirstMatch(from: html, pattern: pattern) {
                return name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ""
    }

    /// Returns the total citation count, or nil when the real stats cell is absent.
    /// Returning nil (not 0) is deliberate: the caller must fail rather than overwrite
    /// a correct value. The old greedy fallbacks (<a>(\d+)</a>, >(\d+)<) matched an
    /// arbitrary number anywhere on the page (a year, a per-paper count) — removed.
    private func extractCitationCount(from html: String) -> Int? {
        let patterns = [
            #"<td[^>]*class="gsc_rsb_std"[^>]*>(\d+)</td>"#,
            #"Citations</a></td><td[^>]*class="gsc_rsb_std"[^>]*>(\d+)</td>"#
        ]

        for pattern in patterns {
            if let citationString = extractFirstMatch(from: html, pattern: pattern),
               let count = Int(citationString) {
                return count
            }
        }

        return nil
    }
    
    private func extractFirstMatch(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        
        let matchRange = match.range(at: 1)
        guard let range = Range(matchRange, in: text) else {
            return nil
        }
        
        return String(text[range])
    }
}