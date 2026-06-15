import Foundation
import SQLite3

/// Single source of truth for where the SQLite database lives on disk.
///
/// Phase 2: the DB lives in the **App Group container** so the un-sandboxed app
/// (writer) and the sandboxed File Provider extension (reader) share one inode.
///
/// Two resolvers for the same file, used from the two sides of the App Group:
/// - The app is **un-sandboxed** (Option B — no entitlement/sandbox change), so
///   it cannot rely on `containerURL(forSecurityApplicationGroupIdentifier:)`
///   (that returns `nil` without the app-groups entitlement). Instead it builds
///   the LITERAL group-container path from the user's home directory.
/// - The extension IS sandboxed and HAS the app-groups entitlement, so it uses
///   `containerURL(forSecurityApplicationGroupIdentifier:)`, which resolves to
///   the same on-disk file.
public enum DatabaseLocation {
    public static let appGroupID = "group.org.sockpuppet.wiki"

    private static let databaseFileName = "WikiFS.sqlite"

    /// The App Group database URL as seen by the **un-sandboxed app**.
    ///
    /// Built from the LITERAL path
    /// `~/Library/Group Containers/group.org.sockpuppet.wiki/WikiFS.sqlite`
    /// (NOT `containerURL(...)`), so the writer needs no app-groups entitlement.
    /// Creates the containing directory if needed.
    public static func appGroupContainerURL() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(databaseFileName, isDirectory: false)
    }

    /// The App Group database URL as seen by the **sandboxed extension**, via the
    /// security API. Resolves to the same inode as `appGroupContainerURL()`.
    /// Returns `nil` if the entitlement/container is unavailable.
    public static func extensionContainerURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }

    /// The legacy Phase 1 database URL in per-user Application Support
    /// (`~/Library/Application Support/WikiFS/WikiFS.sqlite`). Kept as the
    /// migration source and for tests.
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
        return dir.appendingPathComponent(databaseFileName, isDirectory: false)
    }

    /// One-time migration of the Phase 1 Application Support DB into the App
    /// Group container, run by the app at launch BEFORE opening the store.
    ///
    /// Only acts when the container DB is ABSENT and an Application Support DB is
    /// present. It checkpoints the source WAL into the main `.sqlite` file
    /// (`wal_checkpoint(TRUNCATE)`), then copies the single `.sqlite` file across
    /// — so the verified `Home` page is preserved without dragging `-wal`/`-shm`
    /// sidecars into the container.
    ///
    /// If anything fails, the migration is skipped (the app then creates a fresh
    /// `Home` in the container — the gate only needs a Home page present).
    public static func migrateFromApplicationSupportIfNeeded() {
        let fm = FileManager.default
        guard let container = try? appGroupContainerURL() else { return }
        guard !fm.fileExists(atPath: container.path) else { return }
        guard let source = try? applicationSupportURL(),
              fm.fileExists(atPath: source.path) else { return }

        // Checkpoint the source so all committed data lives in the main file.
        checkpointTruncate(at: source)

        do {
            try fm.copyItem(at: source, to: container)
        } catch {
            // Best-effort: leave the container empty; the app bootstraps a fresh
            // DB (with a default Home) at the container path.
            print("DatabaseLocation: migration copy failed: \(error)")
        }
    }

    /// Open `url` read-write once, run `PRAGMA wal_checkpoint(TRUNCATE)`, close.
    private static func checkpointTruncate(at url: URL) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            return
        }
        defer { sqlite3_close(handle) }
        sqlite3_exec(handle, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }
}
