import Foundation

/// Errors thrown by a `WikiStore`. `.sqlite` carries the SQLite result code and
/// the `sqlite3_errmsg` text so failures are diagnosable; `.notFound` is raised
/// when a requested page id has no row.
public enum WikiStoreError: Error, CustomStringConvertible {
    case open(String)
    case sqlite(code: Int32, message: String)
    case notFound(PageID)
    case unexpected(String)

    public var description: String {
        switch self {
        case .open(let m): return "WikiStore open failed: \(m)"
        case .sqlite(let code, let message): return "SQLite error \(code): \(message)"
        case .notFound(let id): return "Page not found: \(id.rawValue)"
        case .unexpected(let m): return "Unexpected: \(m)"
        }
    }
}

/// Read/write storage interface for wiki pages (INITIAL.md §3). The SQLite
/// implementation is the source of truth; the Phase 2 File Provider extension
/// will adopt a read-only subset (`WikiReadStore`) of this.
public protocol WikiStore {
    /// Page summaries ordered by `updated_at` DESC (most-recently-edited first).
    func listPages() throws -> [WikiPageSummary]
    func getPage(id: PageID) throws -> WikiPage
    func createPage(title: String) throws -> WikiPage
    func updatePage(id: PageID, title: String, body: String) throws
    func deletePage(id: PageID) throws
}
