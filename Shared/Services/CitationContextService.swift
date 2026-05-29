import Foundation
import Combine
import SwiftUI
import PDFKit
import NaturalLanguage

// MARK: - Citation Context Service
/// Business logic layer: fetches, caches, and exposes citation context data.
/// Uses Semantic Scholar as the primary source — official API, no scraping.
public class CitationContextService: ObservableObject {
    public static let shared = CitationContextService()

    /// Per-paper loading state keyed by CitingPaper.id
    @Published public var loadingStates: [String: Bool] = [:]
    /// Per-paper error messages keyed by CitingPaper.id
    @Published public var errorMessages: [String: String] = [:]

    private let cacheKeyPrefix = "CitationContext_v1_"
    private let api = SemanticScholarService.shared

    private init() {}

    // MARK: - Fetch with Cache

    /// Returns cached context immediately if fresh; otherwise fetches from Semantic Scholar.
    public func getCitationContext(
        citingPaper: CitingPaper,
        myPaperTitle: String
    ) async -> CitationContext? {
        let key = cacheKey(citingPaperId: citingPaper.id, myPaperTitle: myPaperTitle)

        // Return cached entry if still fresh
        if let cached = loadFromCache(key: key), !cached.isExpired {
            return cached.context
        }

        await setLoading(true, for: citingPaper.id)

        defer { Task { await self.setLoading(false, for: citingPaper.id) } }

        do {
            let context = try await api.findCitationContext(
                targetPaperTitle: myPaperTitle,
                citingPaperTitle: citingPaper.title
            )
            saveToCache(key: key, entry: CitationContextCacheEntry(
                context: context,
                isUnavailable: context.contexts.isEmpty
            ))
            return context
        } catch SemanticScholarError.rateLimited {
            await setError("rate_limited", for: citingPaper.id)
        } catch {
            await setError(error.localizedDescription, for: citingPaper.id)
            // Cache the failure briefly (1 hour) to avoid hammering the API
            saveToCache(key: key, entry: CitationContextCacheEntry(
                context: nil,
                cachedAt: Date().addingTimeInterval(-6 * 3600), // expire in 1h instead of 7d
                isUnavailable: true
            ))
        }
        return nil
    }

    // MARK: - Background Prefetch

    /// Silently prefetches context for up to 10 papers so the UI feels instant.
    public func prefetch(papers: [CitingPaper], myPaperTitle: String) {
        Task.detached(priority: .background) {
            for paper in papers.prefix(10) {
                let key = self.cacheKey(citingPaperId: paper.id, myPaperTitle: myPaperTitle)
                if let cached = self.loadFromCache(key: key), !cached.isExpired { continue }
                _ = await self.getCitationContext(citingPaper: paper, myPaperTitle: myPaperTitle)
                try? await Task.sleep(nanoseconds: 1_300_000_000) // 1.3 s between requests
            }
        }
    }

    // MARK: - Convenience

    public func isLoading(for citingPaperId: String) -> Bool {
        loadingStates[citingPaperId] ?? false
    }

    /// Load all cached contexts (used by CitationInsightsView)
    public func allCachedContexts() -> [CitationContext] {
        let defaults = UserDefaults.standard
        return defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(cacheKeyPrefix) }
            .compactMap { key -> CitationContext? in
                guard let data = defaults.data(forKey: key),
                      let entry = try? JSONDecoder().decode(CitationContextCacheEntry.self, from: data)
                else { return nil }
                return entry.context
            }
            .sorted { $0.fetchedAt > $1.fetchedAt }
    }

    // MARK: - Batch Fetch for Scholar

    /// Progress tracking for batch fetch
    @Published public var batchProgress: BatchFetchProgress = BatchFetchProgress()

    public struct BatchFetchProgress {
        public var isRunning = false
        public var currentPaperIndex = 0
        public var totalPapers = 0
        public var currentPaperTitle = ""
        public var totalContextsFound = 0
        public var successCount = 0
        public var notFoundCount = 0       // Paper not on Semantic Scholar
        public var rateLimitedCount = 0
        public var errors: [String] = []

        public var fraction: Double {
            guard totalPapers > 0 else { return 0 }
            return Double(currentPaperIndex) / Double(totalPapers)
        }
    }

    /// Result container for batch fetch — Codable for persistence
    public struct BatchCitationResult: Identifiable, Codable {
        public let id: String
        public let myPaperTitle: String          // User's paper that was cited
        public let myPaperYear: Int?
        public let citingPaperTitle: String       // Paper that cites
        public let citingAuthors: [String]
        public let citingYear: Int?
        public let contexts: [String]             // Verbatim quote sentences
        public let intents: [CitationContext.CitationIntent]

        public init(
            id: String = UUID().uuidString,
            myPaperTitle: String,
            myPaperYear: Int?,
            citingPaperTitle: String,
            citingAuthors: [String],
            citingYear: Int?,
            contexts: [String],
            intents: [CitationContext.CitationIntent]
        ) {
            self.id = id
            self.myPaperTitle = myPaperTitle
            self.myPaperYear = myPaperYear
            self.citingPaperTitle = citingPaperTitle
            self.citingAuthors = citingAuthors
            self.citingYear = citingYear
            self.contexts = contexts
            self.intents = intents
        }
    }

    /// Fetch status for a publication's citation analysis
    public enum PublicationFetchStatus: String, Codable {
        case success = "success"
        case notFoundOnSS = "not_found"       // Paper not indexed on Semantic Scholar
        case rateLimited = "rate_limited"
        case error = "error"

        public var displayMessage: String {
            switch self {
            case .success: return ""
            case .notFoundOnSS: return "This paper was not found on Semantic Scholar. It may not be indexed yet."
            case .rateLimited: return "Request was rate-limited. Try again later."
            case .error: return "An error occurred while fetching citation data."
            }
        }
    }

    /// Per-publication citation results for drill-down UI
    public struct PublicationCitationResults: Identifiable, Codable {
        public let id: String
        public let publicationTitle: String
        public let publicationYear: Int?
        public let citationCount: Int?
        public let citingPapers: [BatchCitationResult]
        public let fetchStatus: PublicationFetchStatus
        public let fetchErrorDetail: String?

        public init(id: String, publicationTitle: String, publicationYear: Int?,
                    citationCount: Int?, citingPapers: [BatchCitationResult],
                    fetchStatus: PublicationFetchStatus = .success,
                    fetchErrorDetail: String? = nil) {
            self.id = id
            self.publicationTitle = publicationTitle
            self.publicationYear = publicationYear
            self.citationCount = citationCount
            self.citingPapers = citingPapers
            self.fetchStatus = fetchStatus
            self.fetchErrorDetail = fetchErrorDetail
        }

        public var totalContexts: Int {
            citingPapers.reduce(0) { $0 + $1.contexts.count }
        }

        public var papersWithContexts: Int {
            citingPapers.filter { !$0.contexts.isEmpty }.count
        }
    }

    /// Sort order for citing papers within a publication
    public enum CitingSortOrder: String, CaseIterable {
        case yearDesc = "yearDesc"
        case yearAsc = "yearAsc"
        case contextCountDesc = "contextCountDesc"

        public var displayName: String {
            switch self {
            case .yearDesc: return "Newest First"
            case .yearAsc: return "Oldest First"
            case .contextCountDesc: return "Most Quotes"
            }
        }
    }

    /// Persistent storage wrapper for batch results
    private struct BatchResultsStore: Codable {
        let results: [BatchCitationResult]
        let fetchedAt: Date
        let scholarId: String
    }

    /// Persistent storage for per-publication results
    private struct PubResultsStore: Codable {
        let results: [PublicationCitationResults]
        let fetchedAt: Date
        let scholarId: String
    }

    private let batchStoreKeyPrefix = "BatchCitationResults_v1_"
    private let pubAuthorsKeyPrefix = "PubAuthors_v1_"

    // MARK: - Author Position Filter

    public enum AuthorPositionFilter: String, CaseIterable {
        case all = "all"
        case firstAuthor = "first"
        case coFirstAuthor = "coFirst"
        case correspondingAuthor = "corresponding"

        public var displayName: String {
            switch self {
            case .all: return "All"
            case .firstAuthor: return "First Author"
            case .coFirstAuthor: return "Co-first Author"
            case .correspondingAuthor: return "Corresponding / Last"
            }
        }

        public var icon: String {
            switch self {
            case .all: return "person.3"
            case .firstAuthor: return "1.circle"
            case .coFirstAuthor: return "equal.circle"
            case .correspondingAuthor: return "star.circle"
            }
        }
    }

    /// 学者在论文中的作者角色
    public enum AuthorRole: String, Codable, CaseIterable {
        case firstAuthor = "first"
        case coFirstAuthor = "co_first"      // 共同第一作者（需要星号/标记标识）
        case correspondingAuthor = "corresponding"  // 末位作者（通讯）
        case middleAuthor = "middle"
        case unknown = "unknown"             // 无作者信息

        public var displayName: String {
            switch self {
            case .firstAuthor: return "First Author"
            case .coFirstAuthor: return "Co-First Author"
            case .correspondingAuthor: return "Corresponding"
            case .middleAuthor: return "Middle Author"
            case .unknown: return "Unknown"
            }
        }

        public var icon: String {
            switch self {
            case .firstAuthor: return "1.circle.fill"
            case .coFirstAuthor: return "2.circle.fill"
            case .correspondingAuthor: return "star.circle.fill"
            case .middleAuthor: return "person.circle"
            case .unknown: return "questionmark.circle"
            }
        }

        public var color: Color {
            switch self {
            case .firstAuthor: return .blue
            case .coFirstAuthor: return .green
            case .correspondingAuthor: return .purple
            case .middleAuthor: return .secondary
            case .unknown: return .secondary
            }
        }

        /// 用于 picker 中分组展示的排序顺序
        public var sortOrder: Int {
            switch self {
            case .firstAuthor: return 0
            case .correspondingAuthor: return 1
            case .coFirstAuthor: return 2
            case .middleAuthor: return 3
            case .unknown: return 4
            }
        }
    }

    /// Publication with author info (Semantic Scholar / Google Scholar, optionally
    /// refined with the authoritative complete list from OpenAlex).
    public struct PublicationWithAuthors: Codable, Identifiable {
        public let id: String          // same as PublicationInfo.id
        public let title: String
        public let year: Int?
        public let citationCount: Int?
        public let authors: [String]   // ordered author names

        /// True when `authors` is the complete, authoritative list (from OpenAlex).
        /// SS / GS lists are often truncated, so the "last author == corresponding"
        /// heuristic is only trusted when this is true. Defaults false.
        public var authorListComplete: Bool
        /// OpenAlex is_corresponding for the scholar, when known (authoritative).
        public var correspondingByOpenAlex: Bool?

        public init(
            id: String,
            title: String,
            year: Int?,
            citationCount: Int?,
            authors: [String],
            authorListComplete: Bool = false,
            correspondingByOpenAlex: Bool? = nil
        ) {
            self.id = id
            self.title = title
            self.year = year
            self.citationCount = citationCount
            self.authors = authors
            self.authorListComplete = authorListComplete
            self.correspondingByOpenAlex = correspondingByOpenAlex
        }

        // Custom decode so older cached entries (without the new keys) still load.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            year = try c.decodeIfPresent(Int.self, forKey: .year)
            citationCount = try c.decodeIfPresent(Int.self, forKey: .citationCount)
            authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
            authorListComplete = try c.decodeIfPresent(Bool.self, forKey: .authorListComplete) ?? false
            correspondingByOpenAlex = try c.decodeIfPresent(Bool.self, forKey: .correspondingByOpenAlex)
        }

        /// Strip author name markers (*, †, #, superscripts, etc.) used to denote co-first/corresponding
        private static func stripMarkers(_ name: String) -> (clean: String, hasMarker: Bool) {
            let markers: Set<Character> = ["*", "†", "‡", "#", "§", "¶", "◊"]
            let superscripts: Set<Character> = ["¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹", "⁰"]
            var cleaned = name
            var foundMarker = false
            // Strip leading/trailing markers
            while let first = cleaned.first, markers.contains(first) || superscripts.contains(first) {
                cleaned.removeFirst()
                foundMarker = true
            }
            while let last = cleaned.last, markers.contains(last) || superscripts.contains(last) {
                cleaned.removeLast()
                foundMarker = true
            }
            return (cleaned.trimmingCharacters(in: .whitespaces), foundMarker)
        }

        /// 检测学者在该论文中的作者角色
        /// Rules:
        /// - If markers (*, †) exist on authors: marker at early position → co-first; marker at last position → corresponding
        /// - If no markers: position 0 → first; last position → corresponding; others → middle
        public func detectRole(scholarName: String) -> AuthorRole {
            guard !authors.isEmpty else { return .unknown }
            guard !scholarName.isEmpty else { return .unknown }

            let count = authors.count

            // Parse markers from all authors
            let parsed = authors.map { Self.stripMarkers($0) }
            let hasAnyMarkers = parsed.contains { $0.hasMarker }

            // Find scholar's position(s)
            var scholarIndex: Int? = nil
            for (i, p) in parsed.enumerated() {
                if Self.namesMatch(p.clean, scholarName) {
                    scholarIndex = i
                    break
                }
            }

            guard let idx = scholarIndex else { return .unknown }

            let scholarHasMarker = parsed[idx].hasMarker
            let isFirst = (idx == 0)
            let isLast = (idx == count - 1) && count > 1

            // First author ALWAYS wins. A first author who is also the corresponding
            // author is still labeled 一作 (first), not 通讯. This must be checked
            // before the OpenAlex is_corresponding signal, which is true for many
            // first authors and previously mislabeled them corresponding.
            if isFirst { return .firstAuthor }

            // Authoritative corresponding signal from OpenAlex (non-first authors only).
            if correspondingByOpenAlex == true { return .correspondingAuthor }

            if hasAnyMarkers {
                // A marker on the last author is an explicit corresponding signal,
                // trustworthy even when the list is otherwise incomplete.
                if isLast && scholarHasMarker { return .correspondingAuthor }
                if scholarHasMarker && idx <= 2 {
                    // Early position with marker → co-first
                    return .coFirstAuthor
                }
                // Last without a marker → only trust "corresponding" on a complete list.
                if isLast { return authorListComplete ? .correspondingAuthor : .middleAuthor }
                return .middleAuthor
            } else {
                // No markers. Only call the last author "corresponding" when the list
                // is known complete; otherwise a TRUNCATED middle author would land
                // last and be mis-labeled corresponding — the reported bug.
                if isLast { return authorListComplete ? .correspondingAuthor : .middleAuthor }
                return .middleAuthor
            }
        }

        /// Check if a scholar name matches this publication in a given author position
        public func matchesFilter(_ filter: AuthorPositionFilter, scholarName: String) -> Bool {
            let role = detectRole(scholarName: scholarName)
            switch filter {
            case .all: return true
            case .firstAuthor: return role == .firstAuthor
            case .coFirstAuthor: return role == .coFirstAuthor
            case .correspondingAuthor: return role == .correspondingAuthor
            }
        }

        /// Fuzzy name matching: handles markers, initials with dots, reversed name order
        public static func namesMatch(_ a: String, _ b: String) -> Bool {
            // 1. Strip markers and normalize
            let cleanA = stripMarkers(a).clean
            let cleanB = stripMarkers(b).clean

            // 2. Normalize: remove dots, hyphens in initials, lowercase
            func normalize(_ s: String) -> [String] {
                s.lowercased()
                    .replacingOccurrences(of: ".", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
            }

            let partsA = normalize(cleanA)
            let partsB = normalize(cleanB)
            guard !partsA.isEmpty && !partsB.isEmpty else { return false }

            let lastA = partsA.last!
            let lastB = partsB.last!

            // 3. Last names must match (exact or one is prefix of other for abbreviated names)
            let lastNameMatch = lastA == lastB ||
                (lastA.count >= 2 && lastB.count >= 2 && (lastA.hasPrefix(lastB) || lastB.hasPrefix(lastA)))
            guard lastNameMatch else {
                // Try reversed name order: A="Tao Shen" B="Shen Tao"
                if partsA.count >= 2 && partsB.count >= 2 {
                    if partsA.first! == partsB.last! && partsA.last! == partsB.first! { return true }
                }
                return false
            }

            // 4. If only one part each (just last name), match
            if partsA.count == 1 || partsB.count == 1 { return true }

            // 5. Check first name/initial overlap
            let firstA = partsA.first!
            let firstB = partsB.first!
            // Exact match
            if firstA == firstB { return true }
            // Initial match: "t" matches "tao", "j" matches "john"
            if firstA.count == 1 && firstB.hasPrefix(firstA) { return true }
            if firstB.count == 1 && firstA.hasPrefix(firstB) { return true }
            // First letter match (e.g., "tao" vs "t" already covered, but "tao" vs "ting" would be ambiguous)
            // Only match if one is a single character (initial)
            if firstA.prefix(1) == firstB.prefix(1) && (firstA.count <= 2 || firstB.count <= 2) { return true }

            // 6. Handle middle names: "John A Smith" vs "John Smith" or "J A Smith" vs "John Smith"
            // If first names match, ignore extra middle name parts
            if partsA.count > 2 && partsB.count == 2 {
                if firstA == firstB || (firstA.prefix(1) == firstB.prefix(1) && (firstA.count <= 2 || firstB.count <= 2)) { return true }
            }
            if partsB.count > 2 && partsA.count == 2 {
                if firstA == firstB || (firstA.prefix(1) == firstB.prefix(1) && (firstA.count <= 2 || firstB.count <= 2)) { return true }
            }

            return false
        }
    }

    /// Fetch author info for publications from Semantic Scholar.
    /// Results are cached per scholar.
    @MainActor
    public func fetchPublicationAuthors(
        scholarId: String,
        publications: [PublicationInfo]
    ) async -> [PublicationWithAuthors] {
        // Try loading from cache first — only use if at least some have author data
        if let cached = loadPublicationAuthors(forScholar: scholarId),
           !cached.isEmpty,
           cached.contains(where: { !$0.authors.isEmpty }) {
            return cached
        }

        batchProgress = BatchFetchProgress()
        batchProgress.isRunning = true
        batchProgress.totalPapers = publications.count

        var results: [PublicationWithAuthors] = []

        for (index, pub) in publications.enumerated() {
            batchProgress.currentPaperIndex = index
            batchProgress.currentPaperTitle = pub.title

            do {
                let authors = try await api.fetchPaperAuthors(title: pub.title)
                let pwa = PublicationWithAuthors(
                    id: pub.id,
                    title: pub.title,
                    year: pub.year,
                    citationCount: pub.citationCount,
                    authors: authors.map(\.name)
                )
                results.append(pwa)
            } catch SemanticScholarError.rateLimited {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                // Retry once
                do {
                    let authors = try await api.fetchPaperAuthors(title: pub.title)
                    results.append(PublicationWithAuthors(
                        id: pub.id, title: pub.title, year: pub.year,
                        citationCount: pub.citationCount, authors: authors.map(\.name)
                    ))
                } catch {
                    results.append(PublicationWithAuthors(
                        id: pub.id, title: pub.title, year: pub.year,
                        citationCount: pub.citationCount, authors: []
                    ))
                }
            } catch {
                results.append(PublicationWithAuthors(
                    id: pub.id, title: pub.title, year: pub.year,
                    citationCount: pub.citationCount, authors: []
                ))
            }
        }

        batchProgress.currentPaperIndex = publications.count
        batchProgress.isRunning = false

        // Persist
        savePublicationAuthors(results, forScholar: scholarId)
        return results
    }

    public func savePublicationAuthors(_ pubs: [PublicationWithAuthors], forScholar scholarId: String) {
        if let data = try? JSONEncoder().encode(pubs) {
            UserDefaults.standard.set(data, forKey: pubAuthorsKeyPrefix + scholarId)
        }
    }

    public func loadPublicationAuthors(forScholar scholarId: String) -> [PublicationWithAuthors]? {
        guard let data = UserDefaults.standard.data(forKey: pubAuthorsKeyPrefix + scholarId),
              let pubs = try? JSONDecoder().decode([PublicationWithAuthors].self, from: data)
        else { return nil }
        return pubs
    }

    /// Fetch citation contexts for selected publications using Semantic Scholar.
    /// SS is the only API that provides verbatim citation sentences.
    /// Strategy: resolve paper → fetch all citations with contexts → group by publication.
    /// Results are automatically persisted to UserDefaults after fetch.
    @MainActor
    public func fetchAllContextsForScholar(
        scholarId: String,
        scholarName: String,
        publications: [PublicationInfo],
        selectedIds: Set<String>? = nil
    ) async -> [PublicationCitationResults] {
        var pubs = publications.filter { ($0.citationCount ?? 0) > 0 }
        if let selected = selectedIds {
            pubs = pubs.filter { selected.contains($0.id) }
        }

        batchProgress = BatchFetchProgress()
        batchProgress.isRunning = true
        batchProgress.totalPapers = pubs.count

        var allResults: [PublicationCitationResults] = []

        for (index, pub) in pubs.enumerated() {
            batchProgress.currentPaperIndex = index
            batchProgress.currentPaperTitle = pub.title

            var citingPapers: [BatchCitationResult] = []

            var fetchStatus: PublicationFetchStatus = .success
            var fetchErrorDetail: String? = nil

            do {
                if let ssResult = try await api.fetchAllCitationsWithContext(paperTitle: pub.title) {
                    for ssCiting in ssResult.citations {
                        guard !ssCiting.citingPaper.title.isEmpty else { continue }

                        let contexts = ssCiting.contexts ?? []
                        let intents: [CitationContext.CitationIntent] = Array(Set(
                            (ssCiting.intents ?? []).compactMap { raw -> CitationContext.CitationIntent? in
                                switch raw.lowercased() {
                                case "methodology": return .methodology
                                case "background": return .background
                                case "result": return .result
                                case "extends": return .extends
                                default: return .unknown
                                }
                            }
                        ))

                        citingPapers.append(BatchCitationResult(
                            myPaperTitle: pub.title,
                            myPaperYear: pub.year,
                            citingPaperTitle: ssCiting.citingPaper.title,
                            citingAuthors: (ssCiting.citingPaper.authors ?? []).map(\.name),
                            citingYear: ssCiting.citingPaper.year,
                            contexts: contexts,
                            intents: intents
                        ))
                    }
                    batchProgress.successCount += 1
                    batchProgress.totalContextsFound += citingPapers.reduce(0) { $0 + $1.contexts.count }
                    NSLog("📖 [Insights] SS: %d citing papers, %d contexts for '%@'",
                          citingPapers.count,
                          citingPapers.reduce(0) { $0 + $1.contexts.count },
                          String(pub.title.prefix(50)))
                } else {
                    fetchStatus = .notFoundOnSS
                    batchProgress.notFoundCount += 1
                    NSLog("📖 [Insights] SS: paper not found for '%@'", String(pub.title.prefix(50)))
                }
            } catch SemanticScholarError.rateLimited {
                fetchStatus = .rateLimited
                fetchErrorDetail = "Rate limited by Semantic Scholar API"
                batchProgress.rateLimitedCount += 1
                batchProgress.errors.append("Rate limited — waiting before retry")
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                fetchStatus = .error
                fetchErrorDetail = error.localizedDescription
                batchProgress.notFoundCount += 1
                batchProgress.errors.append("\(String(pub.title.prefix(40))): \(error.localizedDescription)")
                NSLog("📖 [Insights] SS error for '%@': %@",
                      String(pub.title.prefix(50)), error.localizedDescription)
            }

            allResults.append(PublicationCitationResults(
                id: pub.id,
                publicationTitle: pub.title,
                publicationYear: pub.year,
                citationCount: pub.citationCount,
                citingPapers: citingPapers,
                fetchStatus: fetchStatus,
                fetchErrorDetail: fetchErrorDetail
            ))
        }

        batchProgress.currentPaperIndex = pubs.count
        batchProgress.isRunning = false

        savePublicationResults(allResults, forScholar: scholarId)
        return allResults
    }

    // MARK: - Google Scholar Fetch Helper

    /// Fetch citing papers from Google Scholar "Cited By" page (async wrapper).
    private func fetchCitingPapersFromGS(clusterId: String) async -> [CitingPaper]? {
        return await withCheckedContinuation { continuation in
            CitationFetchService.shared.fetchCitingPapersForClusterId(
                clusterId,
                startIndex: 0,
                sortByDate: true
            ) { result in
                switch result {
                case .success(let papers):
                    NSLog("📖 [Insights] Got %d citing papers for cluster %@", papers.count, clusterId)
                    continuation.resume(returning: papers)
                case .failure(let error):
                    NSLog("📖 [Insights] Failed to fetch citing papers for cluster %@: %@",
                          clusterId, error.localizedDescription)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - PDF Citation Extraction

    /// Download a PDF and extract sentences that cite the scholar.
    /// Runs off the main thread. Returns nil if download fails or no citations found.
    private static func extractContextsFromPDF(
        pdfUrl: String,
        scholarLastName: String
    ) async -> [String]? {
        guard let url = URL(string: pdfUrl) else { return nil }

        NSLog("📖 [PDF] Downloading: %@", pdfUrl)

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15.0
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("application/pdf,*/*;q=0.9", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                NSLog("📖 [PDF] HTTP %d for %@",
                      (response as? HTTPURLResponse)?.statusCode ?? 0, pdfUrl)
                return nil
            }

            // Skip very large PDFs (> 15MB)
            guard data.count < 15_000_000 else {
                NSLog("📖 [PDF] Skipping large PDF (%d bytes): %@", data.count, pdfUrl)
                return nil
            }

            // Extract text using PDFKit
            guard let document = PDFDocument(data: data) else {
                NSLog("📖 [PDF] Failed to parse PDF: %@", pdfUrl)
                return nil
            }

            var fullText = ""
            let pageLimit = min(document.pageCount, 40)
            for i in 0..<pageLimit {
                if let page = document.page(at: i),
                   let pageText = page.string {
                    fullText += pageText + "\n"
                }
            }

            guard fullText.count > 200 else {
                NSLog("📖 [PDF] Too little text extracted (%d chars): %@", fullText.count, pdfUrl)
                return nil
            }

            NSLog("📖 [PDF] Extracted %d chars from %d pages: %@", fullText.count, pageLimit, pdfUrl)

            // Find citation sentences
            let sentences = findCitationSentences(in: fullText, scholarLastName: scholarLastName)

            if let sentences = sentences {
                NSLog("📖 [PDF] Found %d citation sentences for '%@'", sentences.count, scholarLastName)
            }
            return sentences
        } catch {
            NSLog("📖 [PDF] Download error for %@: %@", pdfUrl, error.localizedDescription)
            return nil
        }
    }

    /// Find sentences in the paper body that mention the scholar (= citation references).
    /// Removes the References/Bibliography section to avoid false matches.
    private static func findCitationSentences(
        in text: String,
        scholarLastName: String
    ) -> [String]? {
        // 1. Remove the References section (author names appear there too)
        let bodyText = removeReferencesSection(from: text)

        // 2. Normalize: join broken lines from PDF column extraction
        let normalized = normalizePDFText(bodyText)

        // 3. Use NLTokenizer to split into sentences
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized

        var results: [String] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let sentence = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Must contain scholar's last name
            guard sentence.range(of: scholarLastName, options: .caseInsensitive) != nil else {
                return true
            }

            // Filter too short (noise) or too long (parsing artifact)
            guard sentence.count >= 30 && sentence.count <= 2000 else {
                return true
            }

            // Skip obvious reference list entries that slipped through
            let lower = sentence.lowercased()
            if (lower.contains("vol.") || lower.contains("pp.") || lower.contains("doi:") || lower.contains("isbn")) &&
                sentence.range(of: #"^\s*\[?\d+\]?"#, options: .regularExpression) != nil {
                return true
            }

            results.append(sentence)
            return results.count < 10 // cap at 10 citation mentions per paper
        }

        return results.isEmpty ? nil : results
    }

    /// Remove the References/Bibliography section from extracted PDF text
    private static func removeReferencesSection(from text: String) -> String {
        // Look for common section headers that mark the start of references
        let patterns = [
            "\nReferences\n", "\nREFERENCES\n", "\nBibliography\n", "\nBIBLIOGRAPHY\n",
            "\nReferences ", "\nREFERENCES ", "\n참고문헌\n", "\n参考文献\n",
            "\nLiterature Cited\n", "\nWorks Cited\n"
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .caseInsensitive) {
                return String(text[text.startIndex..<range.lowerBound])
            }
        }
        return text
    }

    /// Normalize PDF-extracted text: join broken lines, clean up whitespace
    private static func normalizePDFText(_ text: String) -> String {
        var result = ""
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Paragraph break
                if !result.hasSuffix("\n\n") { result += "\n\n" }
            } else if result.hasSuffix("-") && !result.hasSuffix("--") {
                // Hyphenated word across line break
                result.removeLast()
                result += trimmed
            } else {
                if !result.isEmpty && !result.hasSuffix("\n") {
                    result += " "
                }
                result += trimmed
            }
        }
        return result
    }

    // MARK: - Batch Results Persistence

    /// Save batch results to UserDefaults for a given scholar
    public func saveBatchResults(_ results: [BatchCitationResult], forScholar scholarId: String) {
        let store = BatchResultsStore(results: results, fetchedAt: Date(), scholarId: scholarId)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: batchStoreKeyPrefix + scholarId)
        }
    }

    /// Load previously saved batch results for a scholar. Returns nil if no data exists.
    public func loadBatchResults(forScholar scholarId: String) -> (results: [BatchCitationResult], fetchedAt: Date)? {
        guard let data = UserDefaults.standard.data(forKey: batchStoreKeyPrefix + scholarId),
              let store = try? JSONDecoder().decode(BatchResultsStore.self, from: data)
        else { return nil }
        return (results: store.results, fetchedAt: store.fetchedAt)
    }

    /// Check if we have cached batch results for a scholar
    public func hasBatchResults(forScholar scholarId: String) -> Bool {
        UserDefaults.standard.data(forKey: batchStoreKeyPrefix + scholarId) != nil
    }

    // MARK: - Per-Publication Results Persistence

    private let pubResultsKeyPrefix = "PubCitationResults_v1_"

    public func savePublicationResults(_ results: [PublicationCitationResults], forScholar scholarId: String) {
        let store = PubResultsStore(results: results, fetchedAt: Date(), scholarId: scholarId)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: pubResultsKeyPrefix + scholarId)
        }
    }

    public func loadPublicationResults(forScholar scholarId: String) -> (results: [PublicationCitationResults], fetchedAt: Date)? {
        guard let data = UserDefaults.standard.data(forKey: pubResultsKeyPrefix + scholarId),
              let store = try? JSONDecoder().decode(PubResultsStore.self, from: data)
        else { return nil }
        return (results: store.results, fetchedAt: store.fetchedAt)
    }

    public func clearCache() {
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(cacheKeyPrefix) }
            .forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - Private Helpers

    private func cacheKey(citingPaperId: String, myPaperTitle: String) -> String {
        let slug = myPaperTitle.prefix(60)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: "_")
        return "\(cacheKeyPrefix)\(citingPaperId)_\(slug)"
    }

    private func loadFromCache(key: String) -> CitationContextCacheEntry? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entry = try? JSONDecoder().decode(CitationContextCacheEntry.self, from: data)
        else { return nil }
        return entry
    }

    private func saveToCache(key: String, entry: CitationContextCacheEntry) {
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    @MainActor
    private func setLoading(_ loading: Bool, for id: String) {
        loadingStates[id] = loading
    }

    @MainActor
    private func setError(_ message: String, for id: String) {
        errorMessages[id] = message
    }
}
