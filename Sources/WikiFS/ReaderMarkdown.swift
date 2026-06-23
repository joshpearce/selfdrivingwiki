import Foundation
import WikiFSCore

/// The footnote-expand + wiki-link-linkify pre-pass shared by both readers
/// (native `MarkdownPreview` and the web `SourceWebView`), so wiki links and
/// footnotes behave identically regardless of which reader renders them.
///
/// `isResolved` drives resolved-vs-ghost link styling. The native reader passes
/// the store's page/source existence; the web reader currently passes a constant
/// `true` (it can't call the `@MainActor` store from its off-main convert task),
/// so missing links aren't dimmed there yet — ghost coloring for the web reader
/// is a follow-up.
enum ReaderMarkdown {
    static func prepared(
        _ raw: String,
        isResolved: (String, WikiLinkParser.ParsedLink.LinkType) -> Bool
    ) -> String {
        let renderedFootnotes = WikiFootnoteMarkdown.rendered(raw)
        let body = WikiLinkMarkdown.linkified(renderedFootnotes.bodyMarkdown, isResolved: isResolved)
        guard !renderedFootnotes.footnotes.isEmpty else { return body }
        let footnotes = renderedFootnotes.footnotes
            .map { "\($0.number). \(WikiLinkMarkdown.linkified($0.markdown, isResolved: isResolved))" }
            .joined(separator: "\n")
        return "\(body)\n\n---\n\n\(footnotes)"
    }
}
