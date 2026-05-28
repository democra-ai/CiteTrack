import Foundation
import Combine

public enum AnalysisServiceError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decode(String)
    case timeout
    case cancelled
    case noCitingPapers

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid analysis API URL"
        case .http(let code, let body):
            return "Analysis API HTTP \(code): \(body.prefix(200))"
        case .decode(let msg): return "Analysis response decode failed: \(msg)"
        case .timeout: return "Analysis job timed out"
        case .cancelled: return "Analysis cancelled"
        case .noCitingPapers: return "No citing papers to analyze"
        }
    }
}

private struct AnalyzeRequestBody: Encodable {
    let scholarId: String
    let scholarName: String
    let scholarAffiliation: String?
    let publications: [Publication]
    let citingPapers: [CitingPaperPayload]
    let enrichedCitingPapers: [EnrichedCitingPaper]?

    struct Publication: Encodable {
        let id: String
        let title: String
        let year: Int?
        let citationCount: Int?
    }

    struct CitingPaperPayload: Encodable {
        let id: String
        let title: String
        let authors: [String]
        let year: Int?
        let venue: String?
        let citationCount: Int?
        let abstract: String?
        let scholarUrl: String?
        let pdfUrl: String?
    }
}

public final class CiteTrackAnalysisService {
    public static let shared = CiteTrackAnalysisService()

    private let session: URLSession

    // Credentials are read from `CiteTrackAPIConfig` (which supports env/Info.plist
    // overrides and is the single rotation point).
    private var baseURL: URL { CiteTrackAPIConfig.baseURL }
    private var clientId: String { CiteTrackAPIConfig.clientId }
    private var clientSecret: String { CiteTrackAPIConfig.clientSecret }

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 180
        session = URLSession(configuration: cfg)
    }

    // MARK: - Public API

    /// Submit a fresh analysis. Returns the job ID; poll `pollUntilDone` to wait for completion.
    /// `enrichedCitingPapers` is optional: when present, the worker uses it directly and
    /// skips its own OpenAlex calls (which are heavily rate-limited from CF's shared egress IP).
    public func startAnalysis(
        scholar: Scholar,
        publications: [ScholarPublication],
        citingPapers: [CitingPaper],
        enrichedCitingPapers: [EnrichedCitingPaper]? = nil
    ) async throws -> String {
        guard !citingPapers.isEmpty else { throw AnalysisServiceError.noCitingPapers }

        let body = AnalyzeRequestBody(
            scholarId: scholar.id,
            scholarName: scholar.name,
            scholarAffiliation: nil,
            publications: publications.map {
                .init(id: $0.id, title: $0.title, year: $0.year, citationCount: $0.citationCount)
            },
            citingPapers: citingPapers.map {
                .init(
                    id: $0.id,
                    title: $0.title,
                    authors: $0.authors,
                    year: $0.year,
                    venue: $0.venue,
                    citationCount: $0.citationCount,
                    abstract: $0.abstract,
                    scholarUrl: $0.scholarUrl,
                    pdfUrl: $0.pdfUrl
                )
            },
            enrichedCitingPapers: enrichedCitingPapers
        )

        var req = try makeRequest(path: "/v1/analyze", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
        do {
            let decoded = try JSONDecoder().decode(AnalysisJobResponse.self, from: data)
            return decoded.jobId
        } catch {
            throw AnalysisServiceError.decode(String(describing: error))
        }
    }

    public func fetchJobStatus(jobId: String) async throws -> AnalysisJobStatus {
        let req = try makeRequest(path: "/v1/jobs/\(jobId)", method: "GET")
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
        do {
            return try JSONDecoder().decode(AnalysisJobStatus.self, from: data)
        } catch {
            throw AnalysisServiceError.decode(String(describing: error))
        }
    }

    /// Poll the job until it reaches "done" or "error". `progress` callback receives the most recent status.
    public func pollUntilDone(
        jobId: String,
        pollInterval: TimeInterval = 3,
        maxWait: TimeInterval = 300,
        progress: ((AnalysisJobStatus) -> Void)? = nil
    ) async throws -> AnalysisJobStatus {
        let start = Date()
        while Date().timeIntervalSince(start) < maxWait {
            let status = try await fetchJobStatus(jobId: jobId)
            progress?(status)
            if status.status == "done" || status.status == "error" {
                return status
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw AnalysisServiceError.timeout
    }

    /// Fetch the latest computed analysis result for a scholar (the most recent "done" job).
    public func fetchLatestResult(scholarId: String) async throws -> AnalysisResult? {
        let req = try makeRequest(path: "/v1/scholars/\(scholarId)/analysis", method: "GET")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try Self.check(response, data: data)
        struct Wrapper: Decodable { let result: AnalysisResult }
        do {
            return try JSONDecoder().decode(Wrapper.self, from: data).result
        } catch {
            throw AnalysisServiceError.decode(String(describing: error))
        }
    }

    /// Convenience: start + poll + return result.
    public func runAnalysis(
        scholar: Scholar,
        publications: [ScholarPublication],
        citingPapers: [CitingPaper],
        enrichedCitingPapers: [EnrichedCitingPaper]? = nil,
        progress: ((AnalysisJobStatus) -> Void)? = nil
    ) async throws -> AnalysisResult {
        let jobId = try await startAnalysis(
            scholar: scholar,
            publications: publications,
            citingPapers: citingPapers,
            enrichedCitingPapers: enrichedCitingPapers
        )
        let final = try await pollUntilDone(jobId: jobId, progress: progress)
        if final.status == "error" {
            throw AnalysisServiceError.http(0, final.error ?? "analysis failed")
        }
        guard let result = try await fetchLatestResult(scholarId: scholar.id) else {
            throw AnalysisServiceError.http(404, "no result for scholar after done")
        }
        return result
    }

    // MARK: - 海优 scoring

    /// Submit a 海优 simulated-scoring job. Requires an analysis to already exist
    /// for the scholar (run `runAnalysis` first).
    public func startHaiyouScore(
        scholarId: String,
        scholarName: String?,
        cvText: String?,
        returnPlanText: String?,
        representativePapers: [RepresentativePaperInput]
    ) async throws -> String {
        struct Body: Encodable {
            let scholarName: String?
            let cvText: String?
            let returnPlanText: String?
            let representativePapers: [RepresentativePaperInput]
        }
        var req = try makeRequest(
            path: "/v1/scholars/\(scholarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? scholarId)/haiyou-score",
            method: "POST"
        )
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            Body(
                scholarName: scholarName,
                cvText: cvText?.isEmpty == true ? nil : cvText,
                returnPlanText: returnPlanText?.isEmpty == true ? nil : returnPlanText,
                representativePapers: representativePapers
            )
        )
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
        do {
            return try JSONDecoder().decode(AnalysisJobResponse.self, from: data).jobId
        } catch {
            throw AnalysisServiceError.decode(String(describing: error))
        }
    }

    public func fetchLatestHaiyouScore(scholarId: String) async throws -> HaiyouScoreReport? {
        let req = try makeRequest(
            path: "/v1/scholars/\(scholarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? scholarId)/haiyou-score",
            method: "GET"
        )
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try Self.check(response, data: data)
        do {
            return try JSONDecoder().decode(HaiyouScoreReport.self, from: data)
        } catch {
            throw AnalysisServiceError.decode(String(describing: error))
        }
    }

    /// Convenience: start + poll + fetch the 海优 score report.
    public func runHaiyouScore(
        scholarId: String,
        scholarName: String?,
        cvText: String?,
        returnPlanText: String?,
        representativePapers: [RepresentativePaperInput],
        progress: ((AnalysisJobStatus) -> Void)? = nil
    ) async throws -> HaiyouScoreReport {
        let jobId = try await startHaiyouScore(
            scholarId: scholarId,
            scholarName: scholarName,
            cvText: cvText,
            returnPlanText: returnPlanText,
            representativePapers: representativePapers
        )
        let final = try await pollUntilDone(jobId: jobId, progress: progress)
        if final.status == "error" {
            throw AnalysisServiceError.http(0, final.error ?? "scoring failed")
        }
        guard let report = try await fetchLatestHaiyouScore(scholarId: scholarId) else {
            throw AnalysisServiceError.http(404, "no score report after done")
        }
        return report
    }

    // MARK: - Internal

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AnalysisServiceError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(clientId, forHTTPHeaderField: "CF-Access-Client-Id")
        req.setValue(clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisServiceError.http(http.statusCode, body)
        }
    }
}
