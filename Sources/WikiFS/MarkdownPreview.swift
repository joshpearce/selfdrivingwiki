import SwiftUI
import Textual
import WikiFSCore

/// Live, read-only render of the page body. Regex preprocessing (footnote
/// expansion + wiki-link linkification) runs in a detached task so the view
/// shell appears immediately and the rendered text fills in after. For large
/// documents this avoids blocking the main thread during body evaluation.
///
/// Anchor scrolling: `StructuredText.Heading` already applies `.id(slug)` via
/// Textual (`Heading.swift:24`); `NumberedParagraphStyle` applies `.id("p\(n)")`
/// to paragraphs. The block list (via `AnchorBlock.parse`) maps fragments to ids.
struct MarkdownPreview: View {
    @Bindable var store: WikiStoreModel
    let markdown: String
    var contentInset: Bool = true
    /// The current selection this preview is rendering (page id or source id).
    /// Used to match against `store.pendingScrollAnchor`.
    var currentSelection: WikiSelection? = nil

    @State private var renderedBody: String?
    @State private var renderTaskKey: String?
    @State private var blocks: [AnchorBlock] = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PageEditorMetrics.sectionSpacing) {
                    if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Nothing to preview yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let body = renderedBody {
                        StructuredText(markdown: body)
                            .id(body)
                            .textual.paragraphStyle(NumberedParagraphStyle())
                            .textual.textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .frame(maxWidth: contentInset ? PageEditorMetrics.readableContentWidth : .infinity,
                       alignment: .leading)
                .padding(contentInset ? PageEditorMetrics.contentInset : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .environment(\.openURL, OpenURLAction { url in
                // Same-page anchor: scroll within current preview.
                if WikiLinkMarkdown.isSamePageAnchor(url),
                   let frag = WikiLinkMarkdown.fragment(from: url),
                   let id = resolveAnchor(frag, in: blocks) {
                    proxy.scrollTo(id, anchor: .top)
                    return .handled
                }
                guard let title = WikiLinkMarkdown.target(from: url) else {
                    if WikiFootnoteMarkdown.isFootnoteURL(url) {
                        return .handled
                    }
                    return .systemAction
                }
                let frag = WikiLinkMarkdown.fragment(from: url)
                switch WikiLinkMarkdown.resolvedKind(from: url) {
                case .page:   store.selectPage(byTitle: title, anchor: frag)
                case .source: store.selectSource(byDisplayName: title, anchor: frag)
                case nil:     break
                }
                return .handled
            })
            .task(id: markdown) {
                let captured = markdown
                let key = UUID().uuidString
                renderTaskKey = key
                await Task.yield()
                guard renderTaskKey == key else { return }
                NumberedParagraphStyle.resetCounter()
                renderedBody = renderMarkdown(captured)
                blocks = AnchorBlock.parse(renderedBody ?? captured)
                await Task.yield()
                // Consume pending scroll anchor (set by selectPage/Source).
                if let frag = store.consumePendingScrollAnchor(for: currentSelection),
                   let id = resolveAnchor(frag, in: blocks) {
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    @MainActor
    private func renderMarkdown(_ raw: String) -> String {
        let renderedFootnotes = WikiFootnoteMarkdown.rendered(raw)
        let body = WikiLinkMarkdown.linkified(renderedFootnotes.bodyMarkdown) { [weak store] name, kind in
            kind == .source ? store?.sourceExists(displayName: name) ?? false : store?.pageExists(title: name) ?? false
        }
        guard !renderedFootnotes.footnotes.isEmpty else { return body }
        let footnotes = renderedFootnotes.footnotes
            .map { "\($0.number). \(WikiLinkMarkdown.linkified($0.markdown) { [weak store] n, k in k == .source ? store?.sourceExists(displayName: n) ?? false : store?.pageExists(title: n) ?? false })" }
            .joined(separator: "\n")
        return "\(body)\n\n---\n\n\(footnotes)"
    }
}

#Preview {
    let url = URL.temporaryDirectory.appending(path: "preview-\(UUID().uuidString).sqlite")
    let store = try! SQLiteWikiStore(databaseURL: url)
    let model = WikiStoreModel(store: store)
    return MarkdownPreview(
        store: model,
        markdown: "# Hello\n\nThis is **bold**, a [[Real Page]] and a [[Ghost Page]]."
    )
    .frame(width: 360, height: 240)
}
