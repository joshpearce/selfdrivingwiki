import FileProvider

/// Static, hardcoded file tree for the spike. The real app replaces this with
/// a read-only SQLite-backed projection (see plans/BRINGUP.md Phase 2). Item
/// identifiers are stable strings; paths are derived, never identity.
enum Catalog {
    struct Node {
        let parent: NSFileProviderItemIdentifier
        let name: String
        let isFolder: Bool
        let content: String
    }

    private static let pages = NSFileProviderItemIdentifier("pages")

    static let nodes: [String: Node] = [
        "readme": Node(parent: .rootContainer, name: "README.md", isFolder: false, content: """
        # WikiFS — File Provider spike

        If you can `cat` this from Terminal, the macOS File Provider extension
        is working end to end: domain registered, enumerator listing items,
        content materialized on demand.

        This content is **static and hardcoded** in the extension. The real app
        serves wiki pages out of SQLite. This file only exists to prove the
        plumbing before we build the real thing.
        """),
        "hello": Node(parent: .rootContainer, name: "hello.txt", isFolder: false,
                      content: "hello from the WikiFS file provider extension\n"),
        "pages": Node(parent: .rootContainer, name: "pages", isFolder: true, content: ""),
        "page-home": Node(parent: pages, name: "Home.md", isFolder: false, content: """
        # Home

        A pretend wiki page, served from inside the File Provider extension at
        `pages/Home.md`.
        """),
    ]

    static func item(for id: NSFileProviderItemIdentifier) -> WikiFSItem? {
        if id == .rootContainer {
            return WikiFSItem(id: .rootContainer, parent: .rootContainer, name: "WikiFS", isFolder: true, size: 0)
        }
        guard let node = nodes[id.rawValue] else { return nil }
        return WikiFSItem(id: id, parent: node.parent, name: node.name,
                          isFolder: node.isFolder, size: node.content.utf8.count)
    }

    static func children(of container: NSFileProviderItemIdentifier) -> [NSFileProviderItem] {
        nodes
            .filter { $0.value.parent == container }
            .sorted { $0.key < $1.key }
            .map { key, node in
                WikiFSItem(id: NSFileProviderItemIdentifier(key), parent: node.parent,
                           name: node.name, isFolder: node.isFolder, size: node.content.utf8.count)
            }
    }

    static func content(for id: NSFileProviderItemIdentifier) -> Data? {
        guard let node = nodes[id.rawValue], !node.isFolder else { return nil }
        return Data(node.content.utf8)
    }
}
