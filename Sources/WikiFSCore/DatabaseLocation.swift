import Foundation

/// Single source of truth for where the SQLite database lives on disk.
///
/// Phase 1 (this phase) keeps the DB in the per-user Application Support
/// directory: `~/Library/Application Support/WikiFS/WikiFS.sqlite`. No sandbox,
/// no App Group entitlement — that's deliberately deferred.
///
/// Phase 2 will add an `appGroupURL()` resolver pointing at the shared
/// container (`~/Library/Group Containers/group.org.sockpuppet.wiki/…`) so the
/// File Provider extension can read the same DB, plus a `migrate(from:to:)`
/// step that moves an existing Application Support DB into the group container
/// once (no data loss when entitlements land).
public enum DatabaseLocation {
    /// The Phase 1 database URL, creating the containing directory if needed.
    public static func applicationSupportURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("WikiFS", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("WikiFS.sqlite", isDirectory: false)
    }
}
