import FileProvider
import UniformTypeIdentifiers

/// Read-only `NSFileProviderItem` backed by a resolved `ProjectedNode`.
/// Everything the system needs to show a file/folder in the projection and
/// decide when to re-fetch content. Static-but-correct versions so the FIRST
/// read materializes the right bytes (dynamic change-signaling is Phase 3).
final class WikiFSItem: NSObject, NSFileProviderItem {
    private let node: ProjectedNode

    init(node: ProjectedNode) {
        self.node = node
    }

    var itemIdentifier: NSFileProviderItemIdentifier { node.id }
    var parentItemIdentifier: NSFileProviderItemIdentifier { node.parent }
    var filename: String { node.name }

    var contentType: UTType {
        if node.isFolder { return .folder }
        if node.name.hasSuffix(".md") { return UTType(filenameExtension: "md") ?? .plainText }
        return .plainText
    }

    // Read-only: folders can be enumerated, files can be read. Nothing else.
    var capabilities: NSFileProviderItemCapabilities {
        node.isFolder ? [.allowsReading, .allowsContentEnumerating] : .allowsReading
    }

    // NEVER nil for files — a wrong/absent size truncates `cat`.
    var documentSize: NSNumber? { node.isFolder ? nil : NSNumber(value: node.size) }

    var creationDate: Date? { node.created }
    var contentModificationDate: Date? { node.modified }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: node.contentVersion,
                                  metadataVersion: node.metadataVersion)
    }
}
