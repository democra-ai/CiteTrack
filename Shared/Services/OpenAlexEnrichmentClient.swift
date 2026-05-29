import Foundation

// MARK: - Public enriched-data types
// These mirror the shape the citetrack-api worker accepts so they can be passed
// through transparently. They also allow the iOS app to render institution and
// notable-scholar metadata locally without waiting on the server.

public struct EnrichedInstitution: Codable, Hashable {
    public let openalexId: String?
    public let rorId: String?
    public let displayName: String
    public let countryCode: String?
    public let type: String?
}

public struct EnrichedAuthor: Codable, Hashable {
    public let displayName: String
    public let openalexId: String?
    public let orcid: String?
    public let hIndex: Int?
    public let citedByCount: Int?
    public let worksCount: Int?
    public let institutions: [EnrichedInstitution]
}

public struct EnrichedCitingPaper: Codable, Hashable {
    /// matches the iOS CitingPaper.id sent to the worker so it can correlate
    public let id: String
    public let openalexWorkId: String?
    public let abstract: String?
    public let citationCount: Int?
    public let authors: [EnrichedAuthor]
    /// Venue (journal / conference / repository) the citing paper appeared in,
    /// from OpenAlex primary_location.source. Powers the "top venues" metric.
    public let venueName: String?
    public let venueType: String?

    public init(
        id: String,
        openalexWorkId: String?,
        abstract: String?,
        citationCount: Int?,
        authors: [EnrichedAuthor],
        venueName: String? = nil,
        venueType: String? = nil
    ) {
        self.id = id
        self.openalexWorkId = openalexWorkId
        self.abstract = abstract
        self.citationCount = citationCount
        self.authors = authors
        self.venueName = venueName
        self.venueType = venueType
    }
}

/// Authoritative author-position info for one of the scholar's OWN publications,
/// resolved from OpenAlex (complete author list, author_position, is_corresponding).
/// Used to fix mis-detection caused by truncated/incomplete Semantic Scholar or
/// Google Scholar author lists.
public struct OpenAlexOwnAuthorship: Hashable {
    public let authorPosition: String?   // "first" | "middle" | "last"
    public let isCorresponding: Bool
    public let authorNames: [String]     // complete, ordered author display names
    public let matchedIndex: Int?        // scholar's index within authorNames
}

// MARK: - OpenAlex enrichment client
// Runs on the user's device — uses the user's IP, not the shared Cloudflare egress
// IP that gets aggressively rate-limited by OpenAlex.

public final class OpenAlexEnrichmentClient {
    public static let shared = OpenAlexEnrichmentClient()

    private let baseURL = URL(string: "https://api.openalex.org")!
    private let mailto = "tao.shen@zju.edu.cn"
    private let session: URLSession

    private let workCacheKey = "OpenAlexEnrichmentCache_works_v1"
    private let authorCacheKey = "OpenAlexEnrichmentCache_authors_v1"
    private let workCacheTTL: TimeInterval = 60 * 60 * 24 * 30
    private let authorCacheTTL: TimeInterval = 60 * 60 * 24 * 14

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 45
        cfg.httpAdditionalHeaders = [
            "User-Agent": "CiteTrack-iOS/1.0 (mailto:tao.shen@zju.edu.cn)",
            "Accept": "application/json",
        ]
        session = URLSession(configuration: cfg)
    }

    // MARK: - Public entry

    /// Enrich a batch of citing papers. Caller should pass `progress` to surface
    /// per-paper completion to the UI. Returns one entry per paper that was
    /// successfully matched in OpenAlex; unmatched papers are silently skipped
    /// (the worker will fall back to its own enrichment for those).
    public func enrich(
        citingPapers: [CitingPaper],
        concurrency: Int = 4,
        progress: ((_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> [EnrichedCitingPaper] {
        guard !citingPapers.isEmpty else { return [] }
        let total = citingPapers.count

        var workCache = loadWorkCache()
        var authorCache = loadAuthorCache()
        let now = Date()

        // Stage 1: resolve each paper to an OpenAlex work
        let resolved: [(String, OpenAlexWork?)] = await runBatched(citingPapers, concurrency: concurrency) { paper -> (String, OpenAlexWork?) in
            let cacheKey = self.workCacheCacheKey(title: paper.title, year: paper.year)
            if let cached = workCache[cacheKey], cached.expiresAt > now, let work = cached.work {
                return (paper.id, work)
            }
            let work = await self.searchWork(title: paper.title, year: paper.year)
            return (paper.id, work)
        }
        var completed = 0
        for (id, work) in resolved {
            completed += 1
            if let work {
                let cacheKey = workCacheCacheKey(
                    title: citingPapers.first(where: { $0.id == id })?.title ?? "",
                    year: citingPapers.first(where: { $0.id == id })?.year
                )
                workCache[cacheKey] = WorkCacheEntry(work: work, expiresAt: now.addingTimeInterval(workCacheTTL))
            }
            progress?(completed, total * 2)
        }
        saveWorkCache(workCache)

        // Stage 2: for each matched work, fetch its authors' details (deduped)
        let papersWithWorks = resolved.compactMap { (id, work) -> (String, OpenAlexWork)? in
            guard let w = work else { return nil }
            return (id, w)
        }
        var uniqueAuthorIds: [String: OpenAlexAuthorship] = [:]
        for (_, work) in papersWithWorks {
            for ship in work.authorships {
                guard let aid = ship.author.id, !aid.isEmpty else { continue }
                uniqueAuthorIds[aid] = ship
            }
        }
        let toFetch = uniqueAuthorIds.compactMap { (id, ship) -> (String, OpenAlexAuthorship)? in
            if let cached = authorCache[id], cached.expiresAt > now { return nil }
            return (id, ship)
        }
        let authorResults = await runBatched(toFetch, concurrency: concurrency) { (id, _ship) in
            let detail = await self.fetchAuthorDetail(openalexId: id)
            return (id, detail)
        }
        completed = total
        progress?(completed, total * 2)
        for (id, detail) in authorResults {
            if let d = detail {
                authorCache[id] = AuthorCacheEntry(author: d, expiresAt: now.addingTimeInterval(authorCacheTTL))
            }
            completed += 1
            progress?(min(completed, total * 2), total * 2)
        }
        saveAuthorCache(authorCache)

        // Stage 3: assemble EnrichedCitingPaper
        var out: [EnrichedCitingPaper] = []
        for (id, work) in papersWithWorks {
            let abstract = decodeAbstract(inverted: work.abstractInvertedIndex)
            var enrichedAuthors: [EnrichedAuthor] = []
            for ship in work.authorships {
                let cached = ship.author.id.flatMap { authorCache[$0]?.author }
                let h = cached?.summaryStats.hIndex
                let cited = cached?.citedByCount
                let works = cached?.worksCount
                let orcid = ship.author.orcid ?? cached?.orcid
                let institutions: [EnrichedInstitution] = (ship.institutions ?? [OpenAlexInstitution]()).map { (inst: OpenAlexInstitution) -> EnrichedInstitution in
                    EnrichedInstitution(
                        openalexId: inst.id,
                        rorId: inst.ror,
                        displayName: inst.displayName ?? "Unknown",
                        countryCode: inst.countryCode,
                        type: inst.type
                    )
                }
                enrichedAuthors.append(EnrichedAuthor(
                    displayName: ship.author.displayName,
                    openalexId: ship.author.id,
                    orcid: orcid,
                    hIndex: h,
                    citedByCount: cited,
                    worksCount: works,
                    institutions: institutions
                ))
            }
            let source = work.primaryLocation?.source
            out.append(EnrichedCitingPaper(
                id: id,
                openalexWorkId: work.id,
                abstract: abstract,
                citationCount: work.citedByCount,
                authors: enrichedAuthors,
                venueName: source?.displayName,
                venueType: source?.type
            ))
        }
        return out
    }

    // MARK: - Resolve the scholar's own authorship (authoritative)

    /// Resolve one of the scholar's OWN publications in OpenAlex and return the
    /// complete ordered author list plus the scholar's author_position /
    /// is_corresponding. OpenAlex author lists are complete, so this fixes the
    /// "middle author shown as corresponding because the fetched list was
    /// truncated and they happened to be last" problem. Returns nil if the paper
    /// can't be matched in OpenAlex.
    public func resolveOwnAuthorship(title: String, year: Int?, scholarName: String) async -> OpenAlexOwnAuthorship? {
        guard let work = await searchWork(title: title, year: year) else { return nil }
        let names = work.authorships.map { $0.author.displayName }
        guard !names.isEmpty else { return nil }
        var matched: Int? = nil
        for (i, ship) in work.authorships.enumerated() {
            if CitationContextService.PublicationWithAuthors.namesMatch(ship.author.displayName, scholarName) {
                matched = i
                break
            }
        }
        guard let idx = matched else {
            // Scholar not found among OpenAlex authors — still return the complete
            // list (useful for display) but no role signal.
            return OpenAlexOwnAuthorship(authorPosition: nil, isCorresponding: false, authorNames: names, matchedIndex: nil)
        }
        let ship = work.authorships[idx]
        return OpenAlexOwnAuthorship(
            authorPosition: ship.authorPosition,
            isCorresponding: ship.isCorresponding ?? false,
            authorNames: names,
            matchedIndex: idx
        )
    }

    // MARK: - HTTP

    private func searchWork(title: String, year: Int?) async -> OpenAlexWork? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("works"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search", value: String(trimmed.prefix(200))),
            URLQueryItem(name: "per_page", value: "5"),
            URLQueryItem(name: "select", value: "id,title,publication_year,cited_by_count,authorships,abstract_inverted_index,primary_location"),
            URLQueryItem(name: "mailto", value: mailto),
        ]
        guard let url = components?.url else { return nil }
        guard let data = await getJSON(url: url) else { return nil }
        do {
            let resp = try JSONDecoder.openalex.decode(OpenAlexWorksResponse.self, from: data)
            return pickBestWork(target: trimmed, year: year, candidates: resp.results)
        } catch {
            return nil
        }
    }

    private func fetchAuthorDetail(openalexId: String) async -> OpenAlexAuthor? {
        let id = openalexId.replacingOccurrences(of: "https://openalex.org/", with: "")
        var components = URLComponents(url: baseURL.appendingPathComponent("authors").appendingPathComponent(id), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id,display_name,orcid,works_count,cited_by_count,summary_stats,last_known_institutions"),
            URLQueryItem(name: "mailto", value: mailto),
        ]
        guard let url = components?.url else { return nil }
        guard let data = await getJSON(url: url) else { return nil }
        return try? JSONDecoder.openalex.decode(OpenAlexAuthor.self, from: data)
    }

    private func getJSON(url: URL, attempt: Int = 0) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return data }
            if http.statusCode == 200 { return data }
            if (http.statusCode == 429 || http.statusCode >= 500) && attempt < 2 {
                let wait = UInt64(1_500_000_000 * (1 << attempt))
                try await Task.sleep(nanoseconds: wait)
                return await getJSON(url: url, attempt: attempt + 1)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func pickBestWork(target: String, year: Int?, candidates: [OpenAlexWork]) -> OpenAlexWork? {
        guard !candidates.isEmpty else { return nil }
        let norm: (String) -> String = { $0.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
        let normTarget = norm(target)
        let targetTokens = Set(normTarget.split(separator: " ").filter { $0.count > 3 })
        var best: OpenAlexWork?
        var bestScore: Double = -1
        for w in candidates {
            let normTitle = norm(w.title ?? "")
            let tokens = normTitle.split(separator: " ").filter { $0.count > 3 }
            var overlap = 0
            for t in tokens where targetTokens.contains(t) { overlap += 1 }
            var score = Double(overlap)
            if let y = year, let py = w.publicationYear {
                let diff = abs(py - y)
                score += diff <= 1 ? 1.5 : (diff <= 3 ? 0.5 : 0)
            }
            score -= Double(abs(normTitle.count - normTarget.count)) / 100
            if score > bestScore {
                bestScore = score
                best = w
            }
        }
        return best
    }

    // MARK: - Batching

    private func runBatched<Input, Output>(
        _ items: [Input],
        concurrency: Int,
        _ op: @escaping (Input) async -> Output
    ) async -> [Output] {
        guard !items.isEmpty else { return [] }
        let bounded = max(1, min(concurrency, items.count))
        return await withTaskGroup(of: (Int, Output).self) { group in
            var results: [(Int, Output)] = []
            var inflight = 0
            var nextIndex = 0
            for i in 0..<bounded {
                let item = items[i]
                let idx = i
                group.addTask { (idx, await op(item)) }
                inflight += 1
                nextIndex = i + 1
            }
            while inflight > 0 {
                if let value = await group.next() {
                    results.append(value)
                    inflight -= 1
                    if nextIndex < items.count {
                        let item = items[nextIndex]
                        let idx = nextIndex
                        nextIndex += 1
                        group.addTask { (idx, await op(item)) }
                        inflight += 1
                    }
                }
            }
            results.sort { $0.0 < $1.0 }
            return results.map { $0.1 }
        }
    }

    // MARK: - Cache

    private struct WorkCacheEntry: Codable {
        let work: OpenAlexWork?
        let expiresAt: Date
    }

    private struct AuthorCacheEntry: Codable {
        let author: OpenAlexAuthor?
        let expiresAt: Date
    }

    private func workCacheCacheKey(title: String, year: Int?) -> String {
        let t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(t)|\(year ?? 0)"
    }

    private func loadWorkCache() -> [String: WorkCacheEntry] {
        guard let data = UserDefaults.standard.data(forKey: workCacheKey) else { return [:] }
        return (try? JSONDecoder().decode([String: WorkCacheEntry].self, from: data)) ?? [:]
    }

    private func saveWorkCache(_ map: [String: WorkCacheEntry]) {
        let pruned = map.filter { $0.value.expiresAt > Date() }
        if let data = try? JSONEncoder().encode(pruned) {
            UserDefaults.standard.set(data, forKey: workCacheKey)
        }
    }

    private func loadAuthorCache() -> [String: AuthorCacheEntry] {
        guard let data = UserDefaults.standard.data(forKey: authorCacheKey) else { return [:] }
        return (try? JSONDecoder().decode([String: AuthorCacheEntry].self, from: data)) ?? [:]
    }

    private func saveAuthorCache(_ map: [String: AuthorCacheEntry]) {
        let pruned = map.filter { $0.value.expiresAt > Date() }
        if let data = try? JSONEncoder().encode(pruned) {
            UserDefaults.standard.set(data, forKey: authorCacheKey)
        }
    }
}

// MARK: - Abstract inverted-index decode

private func decodeAbstract(inverted: [String: [Int]]?) -> String? {
    guard let inverted, !inverted.isEmpty else { return nil }
    var positions: [(Int, String)] = []
    for (word, idxs) in inverted {
        for i in idxs { positions.append((i, word)) }
    }
    positions.sort { $0.0 < $1.0 }
    let text = positions.map { $0.1 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : text
}

// MARK: - OpenAlex DTOs (snake_case → camelCase via custom decoder)

private struct OpenAlexWorksResponse: Codable {
    let results: [OpenAlexWork]
}

struct OpenAlexWork: Codable, Hashable {
    let id: String?
    let title: String?
    let publicationYear: Int?
    let citedByCount: Int?
    let authorships: [OpenAlexAuthorship]
    let abstractInvertedIndex: [String: [Int]]?
    let primaryLocation: OpenAlexLocation?

    enum CodingKeys: String, CodingKey {
        case id, title
        case publicationYear = "publication_year"
        case citedByCount = "cited_by_count"
        case authorships
        case abstractInvertedIndex = "abstract_inverted_index"
        case primaryLocation = "primary_location"
    }
}

struct OpenAlexLocation: Codable, Hashable {
    let source: OpenAlexSource?
}

struct OpenAlexSource: Codable, Hashable {
    let id: String?
    let displayName: String?
    let type: String?   // "journal" | "conference" | "repository" | "book series" | ...
    let hostOrganizationName: String?

    enum CodingKeys: String, CodingKey {
        case id, type
        case displayName = "display_name"
        case hostOrganizationName = "host_organization_name"
    }
}

struct OpenAlexAuthorship: Codable, Hashable {
    let author: OpenAlexAuthorRef
    let institutions: [OpenAlexInstitution]?
    let authorPosition: String?   // "first" | "middle" | "last"
    let isCorresponding: Bool?

    enum CodingKeys: String, CodingKey {
        case author, institutions
        case authorPosition = "author_position"
        case isCorresponding = "is_corresponding"
    }
}

struct OpenAlexAuthorRef: Codable, Hashable {
    let id: String?
    let displayName: String
    let orcid: String?

    enum CodingKeys: String, CodingKey {
        case id, orcid
        case displayName = "display_name"
    }
}

struct OpenAlexInstitution: Codable, Hashable {
    let id: String?
    let displayName: String?
    let ror: String?
    let countryCode: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, ror, type
        case displayName = "display_name"
        case countryCode = "country_code"
    }
}

struct OpenAlexAuthor: Codable, Hashable {
    let id: String
    let displayName: String
    let orcid: String?
    let worksCount: Int?
    let citedByCount: Int?
    let summaryStats: SummaryStats

    struct SummaryStats: Codable, Hashable {
        let hIndex: Int?
        let i10Index: Int?

        enum CodingKeys: String, CodingKey {
            case hIndex = "h_index"
            case i10Index = "i10_index"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, orcid
        case displayName = "display_name"
        case worksCount = "works_count"
        case citedByCount = "cited_by_count"
        case summaryStats = "summary_stats"
    }
}

extension JSONDecoder {
    static let openalex: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
