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
    public let topVenues: [TopVenue]

    private enum CodingKeys: String, CodingKey {
        case scholarId, generatedAt, citingPapersCount, enrichedPapersCount
        case researchDirections, topCitedPapers, citingInstitutions, notableCiters, topVenues
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
        topVenues = try c.decodeIfPresent([TopVenue].self, forKey: .topVenues) ?? []
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
        try c.encode(topVenues, forKey: .topVenues)
    }
}

public struct TopVenue: Codable, Hashable, Identifiable {
    public let name: String
    public let type: String?       // journal | conference | repository | ...
    public let paperCount: Int
    public let totalCitations: Int
    public var id: String { name }
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

// MARK: - 海优 simulated scoring

public struct RepresentativePaperInput: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var title: String
    public var year: Int?
    public var authorRole: String?
    public var journal: String?
    public var impactFactor: Double?
    public var citationCount: Int?
    public var esiHighlyCited: Bool?

    public init(
        title: String = "",
        year: Int? = nil,
        authorRole: String? = nil,
        journal: String? = nil,
        impactFactor: Double? = nil,
        citationCount: Int? = nil,
        esiHighlyCited: Bool? = nil
    ) {
        self.title = title
        self.year = year
        self.authorRole = authorRole
        self.journal = journal
        self.impactFactor = impactFactor
        self.citationCount = citationCount
        self.esiHighlyCited = esiHighlyCited
    }

    private enum CodingKeys: String, CodingKey {
        case title, year, authorRole, journal, impactFactor, citationCount, esiHighlyCited
    }
}

public struct DimensionScore: Codable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public let maxScore: Double
    public let score: Double
    public let confidence: String
    public let reasoning: String
    public let evidence: [String]
    public let suggestions: [String]
    public var id: String { key }
}

public struct HaiyouDataCompleteness: Codable, Hashable {
    public let hasAnalysis: Bool
    public let hasCvText: Bool
    public let hasReturnPlan: Bool
    public let representativePaperCount: Int
}

public struct HaiyouScoreReport: Codable, Hashable {
    public let scholarId: String
    public let generatedAt: Date
    public let dimensions: [DimensionScore]
    public let totalScore: Double
    public let maxTotal: Double
    public let fundingPrediction: String // priority | approved | rejected
    public let overallAssessment: String
    public let topSuggestions: [String]
    public let dataCompleteness: HaiyouDataCompleteness

    private enum CodingKeys: String, CodingKey {
        case scholarId, generatedAt, dimensions, totalScore, maxTotal
        case fundingPrediction, overallAssessment, topSuggestions, dataCompleteness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scholarId = try c.decode(String.self, forKey: .scholarId)
        let ts = try c.decodeIfPresent(Int64.self, forKey: .generatedAt) ?? 0
        generatedAt = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        dimensions = try c.decodeIfPresent([DimensionScore].self, forKey: .dimensions) ?? []
        totalScore = try c.decode(Double.self, forKey: .totalScore)
        maxTotal = try c.decodeIfPresent(Double.self, forKey: .maxTotal) ?? 100
        fundingPrediction = try c.decode(String.self, forKey: .fundingPrediction)
        overallAssessment = try c.decodeIfPresent(String.self, forKey: .overallAssessment) ?? ""
        topSuggestions = try c.decodeIfPresent([String].self, forKey: .topSuggestions) ?? []
        dataCompleteness = try c.decode(HaiyouDataCompleteness.self, forKey: .dataCompleteness)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scholarId, forKey: .scholarId)
        try c.encode(Int64(generatedAt.timeIntervalSince1970 * 1000), forKey: .generatedAt)
        try c.encode(dimensions, forKey: .dimensions)
        try c.encode(totalScore, forKey: .totalScore)
        try c.encode(maxTotal, forKey: .maxTotal)
        try c.encode(fundingPrediction, forKey: .fundingPrediction)
        try c.encode(overallAssessment, forKey: .overallAssessment)
        try c.encode(topSuggestions, forKey: .topSuggestions)
        try c.encode(dataCompleteness, forKey: .dataCompleteness)
    }
}
