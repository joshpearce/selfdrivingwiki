import FileProvider

/// Enumerates the children of one container from the SQLite projection. A
/// constant sync anchor — no dynamic change tracking this phase (Phase 3).
///
/// Pagination: the children of a container are resolved once into a stable,
/// id-ordered array, then served in fixed-size slices keyed by an integer
/// offset carried in `NSFileProviderPage` (INITIAL §6). root/pages are tiny and
/// fit a single page; by-id/by-title paginate cleanly for large wikis.
final class WikiFSEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private let pageSize = 256

    init(container: NSFileProviderItemIdentifier) {
        self.container = container
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let all = Projection.children(of: container).map { WikiFSItem(node: $0) }
        let start = Self.offset(from: page)
        guard start < all.count else {
            observer.finishEnumerating(upTo: nil)
            return
        }
        let end = min(start + pageSize, all.count)
        observer.didEnumerate(Array(all[start..<end]))
        if end < all.count {
            observer.finishEnumerating(upTo: Self.page(forOffset: end))
        } else {
            observer.finishEnumerating(upTo: nil)
        }
    }

    /// Decode an integer offset from an `NSFileProviderPage`. The initial-page
    /// sentinels decode to 0.
    private static func offset(from page: NSFileProviderPage) -> Int {
        let data = page.rawValue
        if data == NSFileProviderPage.initialPageSortedByName as Data { return 0 }
        if data == NSFileProviderPage.initialPageSortedByDate as Data { return 0 }
        guard let text = String(data: data, encoding: .utf8), let n = Int(text) else { return 0 }
        return n
    }

    private static func page(forOffset offset: Int) -> NSFileProviderPage {
        NSFileProviderPage(Data(String(offset).utf8))
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // Per-edit change signaling is Phase 3. Here the anchor is constant, so
        // a matching anchor means "no changes". A *different* incoming anchor
        // (e.g. a cache from the old spike catalog) is stale: expire it so the
        // daemon discards its cache and does a full re-enumeration via
        // enumerateItems against the SQLite projection.
        if anchor == Self.syncAnchor {
            observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
        } else {
            observer.finishEnumeratingWithError(
                NSError(domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.syncAnchorExpired.rawValue))
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(Self.syncAnchor)
    }

    /// Constant for this phase; distinct from the spike's `"1"` so a cached spike
    /// enumeration is treated as expired and re-synced from SQLite.
    private static let syncAnchor = NSFileProviderSyncAnchor(Data("v2-sqlite".utf8))
}
