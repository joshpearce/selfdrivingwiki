import Foundation

/// Metadata for one ingested file — the verbatim bytes dragged into the app and
/// stored in the `ingested_files` table (NOT a wiki page). The raw `content`
/// BLOB is deliberately NOT part of this summary: it is fetched on demand via
/// `SQLiteWikiStore.ingestedFileContent(id:)` so the list and the projection's
/// `getattr`/enumeration never hold large blobs in memory.
///
/// `id` reuses `PageID` (a ULID-string wrapper) since the ingest id is also a
/// ULID — sortable, so the raw value orders by ingest time. Identifiable +
/// Hashable so it drives a SwiftUI `List`/`ForEach` directly.
public struct IngestedFileSummary: Identifiable, Hashable, Sendable {
    public let id: PageID
    public let filename: String
    /// Lowercased extension with no leading dot (`""` when the name has none).
    public let ext: String
    /// Best-effort UTI→MIME; nil when the extension maps to no known type.
    public let mimeType: String?
    public let byteSize: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let version: Int

    public init(
        id: PageID,
        filename: String,
        ext: String,
        mimeType: String?,
        byteSize: Int,
        createdAt: Date,
        updatedAt: Date,
        version: Int
    ) {
        self.id = id
        self.filename = filename
        self.ext = ext
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}
