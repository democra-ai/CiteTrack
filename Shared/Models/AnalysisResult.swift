import Foundation

// MARK: - Analysis result types
// Mirror of /Backend/citetrack-api/src/types.ts response shape.

public struct AnalysisResult: Codable, Hashable {
    public let scholarId: String
    public let generatedAt: Date
    public let citingPapersCount: Int
    public let enrichedPapersCount: Int
    public let researchDirections: [ResearchDirection]
    public let topCitedPapers: [TopCitedPaper]
    public let citingInstitutions: [CitingInstitution]
    public let notableCiters: [NotableCiter]

    private enum CodingKeys: String, CodingKey {
        case scholarId, generatedAt, citingPapersCount, enrichedPapersCount
        case researchDirections, topCitedPapers, citingInstitutions, notableCiters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scholarId = try c.decode(String.self, forKey: .scholarId)
        let ts = try c.decode(Int64.self, forKey: .generatedAt)
        generatedAt = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        citingPapersCount = try c.decode(Int.self, forKey: .citingPapersCount)
        enrichedPapersCount = try c.decode(Int.self, forKey: .enrichedPapersCount)
        researchDirections = try c.decodeIfPresent([ResearchDirection].self, forKey: .researchDirections) ?? []
        topCitedPapers = try c.decodeIfPresent([TopCitedPaper].self, forKey: .topCitedPapers) ?? []
        citingInstitutions = try c.decodeIfPresent([CitingInstitution].self, forKey: .citingInstitutions) ?? []
        notableCiters = try c.decodeIfPresent([NotableCiter].self, forKey: .notableCiters) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scholarId, forKey: .scholarId)
        try c.encode(Int64(generatedAt.timeIntervalSince1970 * 1000), forKey: .generatedAt)
        try c.encode(citingPapersCount, forKey: .citingPapersCount)
        try c.encode(enrichedPapersCount, forKey: .enrichedPapersCount)
        try c.encode(researchDirections, forKey: .researchDirections)
        try c.encode(topCitedPapers, forKey: .topCitedPapers)
        try c.encode(citingInstitutions, forKey: .citingInstitutions)
        try c.encode(notableCiters, forKey: .notableCiters)
    }
}

public struct ResearchDirection: Codable, Hashable, Identifiable {
    public let clusterIndex: Int
    public let label: String
    public let summary: String
    public let keywords: [String]
    public let paperCount: Int
    public let examplePapers: [ExamplePaper]
    public var id: Int { clusterIndex }
}

public struct ExamplePaper: Codable, Hashable, Identifiable {
    public let id: String
    public let title: String
}

public struct TopCitedPaper: Codable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let authors: [String]
    public let year: Int?
    public let venue: String?
    public let citationCount: Int
    public let scholarUrl: String?
}

public struct CitingInstitution: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let country: String?
    public let type: String?
    public let paperCount: Int
    public let uniqueAuthorCount: Int
}

public struct NotableCiter: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let openalexId: String?
    public let affiliation: String?
    public let hIndex: Int?
    public let citedByCount: Int?
    public let worksCount: Int?
    public let paperCount: Int
    public let examplePapers: [ExamplePaper]
}

public struct AnalysisJobStatus: Codable {
    public let id: String
    public let scholarId: String
    public let status: String
    public let progress: Int
    public let currentStep: String?
    public let error: String?
    public let citingPapersCount: Int
    public let createdAt: Date
    public let startedAt: Date?
    public let completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, scholarId, status, progress, currentStep, error, citingPapersCount
        case createdAt, startedAt, completedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        scholarId = try c.decode(String.self, forKey: .scholarId)
        status = try c.decode(String.self, forKey: .status)
        progress = try c.decode(Int.self, forKey: .progress)
        currentStep = try c.decodeIfPresent(String.self, forKey: .currentStep)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        citingPapersCount = try c.decode(Int.self, forKey: .citingPapersCount)
        createdAt = try Self.decodeMs(c, .createdAt) ?? Date()
        startedAt = try Self.decodeMs(c, .startedAt)
        completedAt = try Self.decodeMs(c, .completedAt)
    }

    private static func decodeMs(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date? {
        guard let v = try c.decodeIfPresent(Int64.self, forKey: key) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(v) / 1000)
    }
}

public struct AnalysisJobResponse: Codable {
    public let jobId: String
    public let status: String
}
