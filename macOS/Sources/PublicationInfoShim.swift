import Foundation

// macOS-target shim. `PublicationInfo` is canonically defined in
// Shared/Managers/CitationManager.swift, but that whole manager (and its export
// subsystem: ExportResult, DataExportManager, …) is not needed on macOS — only
// this small model, which CitationContextService references. Kept byte-identical
// to the canonical definition so behavior matches iOS.
public struct PublicationInfo: Identifiable, Codable {
    public let id: String
    public let title: String
    public let clusterId: String?
    public let citationCount: Int?
    public let year: Int?

    public init(id: String, title: String, clusterId: String?, citationCount: Int?, year: Int?) {
        self.id = id
        self.title = title
        self.clusterId = clusterId
        self.citationCount = citationCount
        self.year = year
    }
}
