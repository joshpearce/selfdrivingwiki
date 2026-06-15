import FileProvider
import Foundation
import WikiFSCore

/// The read-only SQLite-backed projection that replaces the spike's static
/// `Catalog`. Owns:
///   * the identity ↔ row mapping (virtual ids; paths are presentation only),
///   * the static `README.md` bytes,
///   * `node(for:)` / `children(of:)` / `contents(for:)`, each opening a
///     fresh, short-lived read store (INITIAL §10 — the app is the only writer;
///     WAL + `query_only` reads are safe concurrently).
///
/// The id embedded in a page identifier is ALWAYS the full ULID, never the
/// filename — filenames are derived for presentation (INITIAL §6).
enum Projection {

    // MARK: - Identity

    /// Stable virtual identifiers. The page identifiers carry the full ULID.
    enum Identity {
        static let readme = NSFileProviderItemIdentifier("readme")
        static let pages = NSFileProviderItemIdentifier("pages")
        // Container ids come from the shared `WikiFSContainerID` constants so the
        // extension and the app's `signalChange()` can't drift (a mismatch would
        // leave the page list stale after an edit).
        static let pagesByID = NSFileProviderItemIdentifier(WikiFSContainerID.pagesByID)
        static let pagesByTitle = NSFileProviderItemIdentifier(WikiFSContainerID.pagesByTitle)

        static let byIDPrefix = "page-by-id:"
        static let byTitlePrefix = "page-by-title:"

        static func pageByID(_ ulid: String) -> NSFileProviderItemIdentifier {
            NSFileProviderItemIdentifier(byIDPrefix + ulid)
        }

        static func pageByTitle(_ ulid: String) -> NSFileProviderItemIdentifier {
            NSFileProviderItemIdentifier(byTitlePrefix + ulid)
        }

        /// Extract the embedded ULID from a `page-by-id:` / `page-by-title:`
        /// identifier, or nil if it isn't a page identifier.
        static func pageULID(from id: NSFileProviderItemIdentifier) -> String? {
            let raw = id.rawValue
            if raw.hasPrefix(byIDPrefix) { return String(raw.dropFirst(byIDPrefix.count)) }
            if raw.hasPrefix(byTitlePrefix) { return String(raw.dropFirst(byTitlePrefix.count)) }
            return nil
        }
    }

    // MARK: - Static content

    /// The generated `README.md` (INITIAL §5). Static across the DB lifetime, so
    /// a constant version is correct.
    static let readmeBytes = Data("""
    # WikiFS

    This is a read-only filesystem projection of the WikiFS database.

    Useful paths:

    - `pages/by-id/`
    - `pages/by-title/`

    """.utf8)

    /// A constant version stamp for static items (README + folders).
    static let staticVersion = Data("1".utf8)

    // MARK: - Read store

    /// Open a fresh, short-lived read-only store at the App Group container.
    /// Returns nil if the container/DB is unavailable.
    private static func openReadStore() -> SQLiteWikiStore? {
        guard let url = DatabaseLocation.extensionContainerURL() else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? SQLiteWikiStore(readOnlyURL: url)
    }

    // MARK: - Change token (sync anchor)

    /// The whole-database change token used as the File Provider sync anchor.
    /// Advances on ANY page create/update/delete (count:sum — see
    /// `SQLiteWikiStore.changeToken()`). Opens a short-lived read store; returns
    /// a safe `"0:0"` default if the DB is unavailable so the enumerator can
    /// still answer (and a later real token simply differs → re-sync).
    static func changeToken() -> String {
        guard let store = openReadStore(),
              let token = try? store.changeToken() else { return "0:0" }
        return token
    }

    // MARK: - Metadata resolution

    /// Resolve a single item's metadata by identifier.
    static func node(for id: NSFileProviderItemIdentifier) -> ProjectedNode? {
        if id == .rootContainer {
            return .folder(id: .rootContainer, parent: .rootContainer, name: "WikiFS")
        }
        switch id {
        case Identity.readme:
            return .file(id: id, parent: .rootContainer, name: "README.md",
                         size: readmeBytes.count, version: staticVersion,
                         metadataVersion: staticVersion,
                         created: nil, modified: nil)
        case Identity.pages:
            return .folder(id: id, parent: .rootContainer, name: "pages")
        case Identity.pagesByID:
            return .folder(id: id, parent: Identity.pages, name: "by-id")
        case Identity.pagesByTitle:
            return .folder(id: id, parent: Identity.pages, name: "by-title")
        default:
            break
        }
        guard let ulid = Identity.pageULID(from: id),
              let store = openReadStore(),
              let page = try? store.getPage(id: PageID(rawValue: ulid)) else {
            return nil
        }
        return pageFileNode(for: id, page: page)
    }

    /// Build a file node for a page row, under whichever view `id` belongs to.
    private static func pageFileNode(for id: NSFileProviderItemIdentifier,
                                     page: WikiPage) -> ProjectedNode {
        let raw = id.rawValue
        let isByTitle = raw.hasPrefix(Identity.byTitlePrefix)
        let name = isByTitle
            ? FilenameEscaping.byTitleFilename(title: page.title, pageID: page.id.rawValue)
            : FilenameEscaping.byIDFilename(pageID: page.id.rawValue)
        let parent = isByTitle ? Identity.pagesByTitle : Identity.pagesByID
        let body = Data(page.bodyMarkdown.utf8)
        return .file(
            id: id, parent: parent, name: name, size: body.count,
            version: Data(String(page.version).utf8),
            metadataVersion: Data(
                "\(page.title)|\(page.updatedAt.timeIntervalSince1970)|\(page.version)".utf8),
            created: page.createdAt, modified: page.updatedAt
        )
    }

    // MARK: - Enumeration

    /// Children of a container. Root → README + pages; pages → by-id + by-title;
    /// by-id/by-title → one file per page row (ordered by ULID == creation
    /// order). Other containers (files) → empty.
    static func children(of container: NSFileProviderItemIdentifier) -> [ProjectedNode] {
        switch container {
        case .rootContainer:
            return [
                node(for: Identity.readme),
                node(for: Identity.pages),
            ].compactMap { $0 }
        case Identity.pages:
            return [
                node(for: Identity.pagesByID),
                node(for: Identity.pagesByTitle),
            ].compactMap { $0 }
        case Identity.pagesByID:
            return pageNodes(byTitle: false)
        case Identity.pagesByTitle:
            return pageNodes(byTitle: true)
        case .workingSet:
            // The working set is the set of items the daemon actively tracks for
            // change. Re-emit ALL page nodes (both views) so a working-set
            // `enumerateChanges` after a signal carries the new itemVersions and
            // the daemon invalidates its materialized copies.
            return pageNodes(byTitle: false) + pageNodes(byTitle: true)
        default:
            return []
        }
    }

    /// All page rows projected as file nodes under the given view, ordered by id
    /// (ULID == creation order).
    private static func pageNodes(byTitle: Bool) -> [ProjectedNode] {
        guard let store = openReadStore(),
              let pages = try? store.listAllPagesOrderedByID() else { return [] }
        return pages.map { page in
            let id = byTitle ? Identity.pageByTitle(page.id.rawValue)
                             : Identity.pageByID(page.id.rawValue)
            return pageFileNode(for: id, page: page)
        }
    }

    // MARK: - Content

    /// Materialize the bytes for a file identifier. README is static; page files
    /// read the live body from SQLite. Folders return nil.
    static func contents(for id: NSFileProviderItemIdentifier) -> Data? {
        if id == Identity.readme { return readmeBytes }
        guard let ulid = Identity.pageULID(from: id),
              let store = openReadStore(),
              let page = try? store.getPage(id: PageID(rawValue: ulid)) else {
            return nil
        }
        return Data(page.bodyMarkdown.utf8)
    }
}

/// A resolved projection node — a plain value the `WikiFSItem`
/// `NSFileProviderItem` wraps. Carries everything `getattr`/enumeration need.
struct ProjectedNode {
    let id: NSFileProviderItemIdentifier
    let parent: NSFileProviderItemIdentifier
    let name: String
    let isFolder: Bool
    let size: Int
    let contentVersion: Data
    let metadataVersion: Data
    let created: Date?
    let modified: Date?

    static func folder(id: NSFileProviderItemIdentifier,
                       parent: NSFileProviderItemIdentifier,
                       name: String) -> ProjectedNode {
        ProjectedNode(id: id, parent: parent, name: name, isFolder: true, size: 0,
                      contentVersion: Projection.staticVersion,
                      metadataVersion: Projection.staticVersion,
                      created: nil, modified: nil)
    }

    static func file(id: NSFileProviderItemIdentifier,
                     parent: NSFileProviderItemIdentifier,
                     name: String, size: Int,
                     version: Data, metadataVersion: Data,
                     created: Date?, modified: Date?) -> ProjectedNode {
        ProjectedNode(id: id, parent: parent, name: name, isFolder: false, size: size,
                      contentVersion: version, metadataVersion: metadataVersion,
                      created: created, modified: modified)
    }
}
