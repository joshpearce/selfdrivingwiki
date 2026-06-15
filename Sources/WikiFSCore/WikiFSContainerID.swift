import Foundation

/// Shared File Provider container identifiers, as plain strings.
///
/// These are NOT `NSFileProviderItemIdentifier` values (that would drag a
/// `FileProvider` dependency into the core library) — they are just the raw
/// string keys. The File Provider extension (`Projection.Identity`) and the app
/// (`FileProviderSpike.signalChange()`) BOTH reference these so the two sides
/// can never silently drift apart: signaling the wrong container id would leave
/// the page list stale even after a correct enumerator fix.
public enum WikiFSContainerID {
    public static let pagesByID = "pages-by-id"
    public static let pagesByTitle = "pages-by-title"
}
