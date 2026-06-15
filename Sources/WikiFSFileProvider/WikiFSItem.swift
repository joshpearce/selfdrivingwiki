import FileProvider
import UniformTypeIdentifiers

/// Minimal read-only `NSFileProviderItem`. Everything the system needs to show
/// a file/folder in the projection and decide when to re-fetch content.
final class WikiFSItem: NSObject, NSFileProviderItem {
    let id: NSFileProviderItemIdentifier
    let parent: NSFileProviderItemIdentifier
    let name: String
    let isFolder: Bool
    let size: Int

    init(id: NSFileProviderItemIdentifier, parent: NSFileProviderItemIdentifier,
         name: String, isFolder: Bool, size: Int) {
        self.id = id
        self.parent = parent
        self.name = name
        self.isFolder = isFolder
        self.size = size
    }

    var itemIdentifier: NSFileProviderItemIdentifier { id }
    var parentItemIdentifier: NSFileProviderItemIdentifier { parent }
    var filename: String { name }

    var contentType: UTType {
        if isFolder { return .folder }
        if name.hasSuffix(".md") { return UTType(filenameExtension: "md") ?? .plainText }
        return .plainText
    }

    // Read-only: folders can be enumerated, files can be read. Nothing else.
    var capabilities: NSFileProviderItemCapabilities {
        isFolder ? [.allowsReading, .allowsContentEnumerating] : .allowsReading
    }

    var documentSize: NSNumber? { isFolder ? nil : NSNumber(value: size) }

    // Static content, so a constant version is fine. When SQLite backs this,
    // contentVersion = page.version and metadataVersion = hash(title, mtime).
    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: Data("1".utf8), metadataVersion: Data("1".utf8))
    }
}
