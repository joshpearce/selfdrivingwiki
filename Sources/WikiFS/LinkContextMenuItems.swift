import AppKit
import Textual
import WikiFSCore

/// Builds the concrete ``LinkMenuItem``s for a right-clicked link by wiring the
/// pure ``WikiLinkMenuBuilder`` actions to real closures (navigation, semantic
/// search, pasteboard, the system browser).
///
/// Runs on the main actor (AppKit's context-menu path). `store` is captured by
/// the item actions; because the actions are `@MainActor`-isolated and `store`
/// is `@MainActor`, no isolation boundary is crossed.
@MainActor
enum WikiLinkContextMenu {

    static func items(for url: URL, store: WikiStoreModel) -> [LinkMenuItem] {
        var items: [LinkMenuItem] = []
        for action in WikiLinkMenuBuilder.actions(for: url) {
            switch action {
            case .suggest:
                items.append(
                    similarPagesMenu(
                        title: "Suggest…",
                        query: WikiLinkMarkdown.target(from: url) ?? "",
                        store: store))
            case .findSimilar:
                items.append(
                    similarPagesMenu(
                        title: "Find Similar…",
                        query: WikiLinkMarkdown.target(from: url) ?? "",
                        store: store))
            case .copyWikiLink:
                guard let link = WikiLinkMenuBuilder.wikiLinkString(for: url) else { continue }
                items.append(.item("Copy as Wiki Link") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                })
            case .copyFilePath:
                // Not wired in this PR — needs the File Provider mount root +
                // FilenameEscaping plumbed to MarkdownPreview. Tracked as a
                // follow-up (plans/link-context-menus.md).
                continue
            case .openInBrowser:
                items.append(.item("Open in Browser") {
                    NSWorkspace.shared.open(url)
                })
            case .copyLink:
                items.append(.item("Copy Link") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url.absoluteString, forType: .string)
                })
            case .editLink:
                // Not wired in this PR — behavior is an open scope question in
                // plans/link-context-menus.md (jump-to-editor-and-select vs.
                // structural rewrite).
                continue
            }
        }
        return items
    }

    /// A submenu listing the closest pages to `query`; choosing one navigates to
    /// it. Shows a disabled "No similar pages" item when the search is empty so
    /// the submenu is never mysteriously blank.
    private static func similarPagesMenu(
        title: String, query: String, store: WikiStoreModel
    ) -> LinkMenuItem {
        let matches = query.isEmpty
            ? []
            : store.searchSimilar(query: query, limit: 8)

        let submenu: [LinkMenuItem] = matches.isEmpty
            ? [.item("No similar pages", isEnabled: false, action: {})]
            : matches.map { page in
                .item(page.title) { store.selectPage(byTitle: page.title) }
            }

        return .item(title, submenu: submenu)
    }
}
