import Foundation

// MARK: - Semantic Scholar API Service
/// Official Semantic Scholar API client — no scraping, fully compliant.
/// Docs: https://api.semanticscholar.org/graph/v1
/// Free tier: ~100 requests per 5 minutes. Apply for a free API key to increase limits.
public class SemanticScholarService {
    public static let shared = SemanticScholarService()

    private let baseURL = "https://api.semanticscholar.org/graph/v1"
    private let session: URLSession

    /// Throttle: minimum interval between consecutive requests
    private let minRequestInterval: TimeInterval = 1.1
    private var lastRequestTime: Date?
    private let requestQueue = DispatchQueue(label: "com.citetrack.semanticscholar", qos: .userInitiated)

    /// Sliding window rate limiter: track request timestamps over a 5-minute window.
    /// Free tier = 100 req/5min; we use 85 as the safe ceiling.
    private var requestTimestamps: [Date] = []
    private let windowDuration: TimeInterval = 5 * 60   // 5 minutes
    private let maxRequestsPerWindow: Int = 85           // safe margin below 100

    /// Optional free API key — apply at semanticscholar.org for higher rate limits
    public var apiKey: String? = nil

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 40.0
        config.httpAdditionalHeaders = [
            "User-Agent": "CiteTrack-iOS/1.1 (Academic Research App; contact: citetrack@example.com)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Rate Limiting

    /// Per-request throttle (min interval) + sliding window (max requests per 5 min)
    private func throttle() async {
        // 1. Per-request minimum interval
        if let last = lastRequestTime {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minRequestInterval {
                let wait = minRequestInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }

        // 2. Sliding window: purge old timestamps and check capacity
        let now = Date()
        requestTimestamps.removeAll { now.timeIntervalSince($0) > windowDuration }

        if requestTimestamps.count >= maxRequestsPerWindow {
            // Wait until the oldest request in the window expires
            let oldest = requestTimestamps.first!
            let waitUntil = oldest.addingTimeInterval(windowDuration)
            let waitSeconds = waitUntil.timeIntervalSince(now)
            if waitSeconds > 0 {
                print("[SemanticScholar] Sliding window full (\(requestTimestamps.count)/\(maxRequestsPerWindow)). Waiting \(String(format: "%.0f", waitSeconds))s...")
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                // Purge again after waiting
                let afterWait = Date()
                requestTimestamps.removeAll { afterWait.timeIntervalSince($0) > windowDuration }
            }
        }

        let timestamp = Date()
        requestTimestamps.append(timestamp)
        lastRequestTime = timestamp
    }

    /// How many requests remain in the current 5-minute window
    public var remainingRequests: Int {
        let now = Date()
        let recent = requestTimestamps.filter { now.timeIntervalSince($0) <= windowDuration }
        return max(0, maxRequestsPerWindow - recent.count)
    }

    // MARK: - Paper Search by Title

    /// In-memory cache: paper title → SS paperId (avoids repeated searches)
    private var paperIdCache: [String: SSPaperSearchResult] = [:]

    /// Find a paper's Semantic Scholar ID by its title.
    /// Strategy: try /paper/search/match first (lenient rate limit, single best match),
    /// fall back to /paper/search (stricter rate limit, keyword search) if match fails.
    public func searchPaper(title: String) async throws -> SSPaperSearchResult? {
        // Check in-memory cache first
        let cacheKey = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = paperIdCache[cacheKey] {
            return cached
        }

        // 1. Try /paper/search/match — not subject to /paper/search rate limits
        if let result = try? await searchPaperByMatch(title: title) {
            paperIdCache[cacheKey] = result
            return result
        }

        // 2. Fall back to /paper/search — stricter rate limit
        if let result = try await searchPaperByKeyword(title: title) {
            paperIdCache[cacheKey] = result
            return result
        }

        return nil
    }

    /// Title-based matching via /paper/search/match (lenient rate limit)
    /// Returns the single best match or nil if no close match found.
    private func searchPaperByMatch(title: String) async throws -> SSPaperSearchResult? {
        await throttle()

        var components = URLComponents(string: "\(baseURL)/paper/search/match")!
        components.queryItems = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "fields", value: "paperId,title,year,authors")
        ]

        guard let url = components.url else { return nil }

        do {
            let response = try await perform(request: makeRequest(url: url))
            let decoded = try JSONDecoder().decode(SSMatchResponse.self, from: response)
            // Verify the match is actually close enough
            if let match = decoded.data.first,
               titleSimilarity(match.title, title) > 0.4 {
                return SSPaperSearchResult(paperId: match.paperId, title: match.title,
                                           year: match.year, authors: match.authors)
            }
        } catch SemanticScholarError.httpError(404) {
            // No match found — this is normal, fall through
        }
        return nil
    }

    /// Keyword search via /paper/search (stricter rate limit, 100 req/5min)
    private func searchPaperByKeyword(title: String) async throws -> SSPaperSearchResult? {
        await throttle()

        var components = URLComponents(string: "\(baseURL)/paper/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "fields", value: "paperId,title,year,authors"),
            URLQueryItem(name: "limit", value: "5")
        ]

        guard let url = components.url else { throw SemanticScholarError.invalidURL }
        let response = try await perform(request: makeRequest(url: url))

        let decoded = try JSONDecoder().decode(SSSearchResponse.self, from: response)

        // Pick the result whose title most closely matches our query
        return decoded.data.max { a, b in
            titleSimilarity(a.title, title) < titleSimilarity(b.title, title)
        }
    }

    // MARK: - Get Citations with Context
    /// Retrieve papers that cite the given SS paper ID, including verbatim citation sentences.
    public func getCitations(paperId: String, limit: Int = 200) async throws -> [SSCitingPaper] {
        await throttle()

        let urlString = "\(baseURL)/paper/\(paperId)/citations?fields=title,authors,year,contexts,intents&limit=\(limit)"
        guard let url = URL(string: urlString) else { throw SemanticScholarError.invalidURL }

        let response = try await perform(request: makeRequest(url: url))
        let decoded = try JSONDecoder().decode(SSCitationsResponse.self, from: response)
        return decoded.data
    }

    // MARK: - High-Level: Find Citation Context
    /// Given the user's paper title and a citing paper title, return the verbatim citation context.
    /// This is the main entry point used by CitationContextService.
    public func findCitationContext(
        targetPaperTitle: String,
        citingPaperTitle: String
    ) async throws -> CitationContext {
        // Step 1: Resolve user's paper title → Semantic Scholar paper ID
        guard let targetPaper = try await searchPaper(title: targetPaperTitle),
              titleSimilarity(targetPaper.title, targetPaperTitle) > 0.5 else {
            return CitationContext(
                citingPaperTitle: citingPaperTitle,
                citedPaperTitle: targetPaperTitle,
                source: .unavailable
            )
        }

        // Step 2: Fetch all papers citing the target
        let citingPapers = try await getCitations(paperId: targetPaper.paperId)

        // Step 3: Find the specific citing paper by fuzzy title match
        let matched = citingPapers.max { a, b in
            titleSimilarity(a.citingPaper.title, citingPaperTitle) < titleSimilarity(b.citingPaper.title, citingPaperTitle)
        }

        guard let match = matched,
              titleSimilarity(match.citingPaper.title, citingPaperTitle) > 0.5 else {
            return CitationContext(
                citingPaperTitle: citingPaperTitle,
                citedPaperTitle: targetPaperTitle,
                semanticScholarPaperId: targetPaper.paperId,
                source: .semanticScholar
            )
        }

        let intents: [CitationContext.CitationIntent] = Array(
            Set((match.intents ?? []).compactMap { parseIntent($0) })
        )

        return CitationContext(
            citingPaperTitle: citingPaperTitle,
            citedPaperTitle: targetPaperTitle,
            contexts: match.contexts ?? [],
            intents: intents,
            semanticScholarPaperId: targetPaper.paperId,
            source: .semanticScholar
        )
    }

    // MARK: - Batch: All Citations for a Paper
    /// Given a paper title, resolve its Semantic Scholar ID and return ALL citing papers with contexts.
    /// This is the batch entry point used by CitationInsightsView.
    public func fetchAllCitationsWithContext(
        paperTitle: String
    ) async throws -> (paperId: String, authors: [SSAuthor], citations: [SSCitingPaper])? {
        // Step 1: Resolve title → SS paper ID (now also returns authors)
        guard let paper = try await searchPaper(title: paperTitle),
              titleSimilarity(paper.title, paperTitle) > 0.5 else {
            return nil
        }

        // Step 2: Fetch all citing papers with contexts
        let citations = try await getCitations(paperId: paper.paperId)

        return (paperId: paper.paperId, authors: paper.authors ?? [], citations: citations)
    }

    /// Resolve a paper title to its Semantic Scholar metadata including authors.
    /// Used to get author list for filtering publications by author position.
    public func fetchPaperAuthors(title: String) async throws -> [SSAuthor] {
        guard let paper = try await searchPaper(title: title),
              titleSimilarity(paper.title, title) > 0.5 else {
            return []
        }
        return paper.authors ?? []
    }

    // MARK: - Helpers

    private func makeRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        if let key = apiKey { req.setValue(key, forHTTPHeaderField: "x-api-key") }
        return req
    }

    private func perform(request: URLRequest) async throws -> Data {
        var lastError: Error = SemanticScholarError.invalidResponse
        let maxRetries = 3

        for attempt in 0..<maxRetries {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SemanticScholarError.invalidResponse }

            switch http.statusCode {
            case 200:
                return data
            case 429:
                lastError = SemanticScholarError.rateLimited
                if attempt < maxRetries - 1 {
                    // Exponential backoff: 10s, 30s, 60s
                    let backoff: UInt64 = [10, 30, 60][attempt]
                    print("[SemanticScholar] 429 rate limited, retry \(attempt + 1)/\(maxRetries) after \(backoff)s")
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                }
            default:
                throw SemanticScholarError.httpError(http.statusCode)
            }
        }
        throw lastError
    }

    /// Jaccard similarity on word sets — fast and good enough for paper title matching
    private func titleSimilarity(_ a: String, _ b: String) -> Double {
        let stopWords: Set<String> = ["a", "an", "the", "of", "in", "on", "for", "to", "and", "or", "is", "are"]
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { !$0.isEmpty && !stopWords.contains($0) })
        }
        let wa = words(a), wb = words(b)
        guard !wa.isEmpty && !wb.isEmpty else { return 0 }
        let intersection = wa.intersection(wb).count
        let union = wa.union(wb).count
        return Double(intersection) / Double(union)
    }

    private func parseIntent(_ raw: String) -> CitationContext.CitationIntent? {
        switch raw.lowercased() {
        case "methodology": return .methodology
        case "background": return .background
        case "result": return .result
        case "extends": return .extends
        default: return .unknown
        }
    }
}

// MARK: - Response Models

public struct SSSearchResponse: Codable {
    public let data: [SSPaperSearchResult]
}

/// Response from /paper/search/match endpoint
public struct SSMatchResponse: Codable {
    public let data: [SSMatchResult]
}

public struct SSMatchResult: Codable {
    public let paperId: String
    public let title: String
    public let year: Int?
    public let authors: [SSAuthor]?
    public let matchScore: Double?
}

public struct SSPaperSearchResult: Codable {
    public let paperId: String
    public let title: String
    public let year: Int?
    public let authors: [SSAuthor]?
}

public struct SSCitationsResponse: Codable {
    public let data: [SSCitingPaper]
}

public struct SSCitingPaper: Codable {
    public let citingPaper: SSCitingPaperInfo
    public let contexts: [String]?
    public let intents: [String]?
}

public struct SSCitingPaperInfo: Codable {
    public let paperId: String
    public let title: String
    public let year: Int?
    public let authors: [SSAuthor]?
}

public struct SSAuthor: Codable {
    public let authorId: String?
    public let name: String
}

// MARK: - Errors

public enum SemanticScholarError: LocalizedError {
    case invalidURL
    case invalidResponse
    case rateLimited
    case httpError(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .rateLimited: return "Rate limited. Please wait a moment and try again."
        case .httpError(let code): return "HTTP \(code) error from Semantic Scholar"
        }
    }
}
