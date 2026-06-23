import Foundation
import Testing
import Textual
@testable import WikiFSCore
@testable import WikiFS

/// Headless benchmark for the markdown reader render path: isolates the two
/// main-thread, **non-layout** costs — preprocessing (footnote expansion +
/// wiki-link linkification) and Markdown→`AttributedString` parse (Textual) —
/// on a ~512 KB synthetic source, the size at which the reader beachballs (see
/// the "Reader freezes on large source documents" note).
///
/// Layout (SwiftUI measuring every block, with no virtualization) can't be
/// timed headlessly and is the remaining unknown — capture it in Instruments
/// against the `reader.preprocess` signpost (`com.selfdrivingwiki.debug`).
///
/// This answers the load-bearing question: of the ~10 s freeze, how much is
/// parse vs. preprocessing? If parse + preprocessing together are small, layout
/// is the target and the fix is virtualization (#3) or a web view (#4), not
/// off-main parse (#2).
///
/// `@MainActor`: Textual's `MarkupParser` protocol is main-actor-isolated
/// (`Packages/Textual/Sources/Textual/MarkupParser.swift`), so the parse can
/// only be driven from the main actor today — a constraint on the off-main-parse
/// idea, recorded here as a finding.
///
/// Run just this benchmark with:
///
///   swift test --filter ReaderRenderPerfTests
struct ReaderRenderPerfTests {

    private static let targetBytes = 512 * 1024

    @MainActor
    @Test func preprocessVsParseSplitOnLargeSource() {
        let raw = Self.makeLargeMarkdown(targetBytes: Self.targetBytes)
        let bytes = raw.utf8.count
        let parser = AttributedStringMarkdownParser.markdown()

        // Faithfully replay `MarkdownPreview.renderMarkdown` (string cost only —
        // the `isResolved` closure is a constant, so no per-link DB lookup; that
        // lookup is a separate axis measured against a real store).
        func preprocess(_ source: String) -> String {
            let rendered = WikiFootnoteMarkdown.rendered(source)
            let body = WikiLinkMarkdown.linkified(rendered.bodyMarkdown)
            guard !rendered.footnotes.isEmpty else { return body }
            let footnotes = rendered.footnotes
                .map { "\($0.number). \(WikiLinkMarkdown.linkified($0.markdown))" }
                .joined(separator: "\n")
            return "\(body)\n\n---\n\n\(footnotes)"
        }

        // Warm up (regex caches, Foundation Markdown JIT) before timing.
        _ = try? parser.attributedString(for: preprocess(raw))

        // Preprocess: median of 5 runs (median ignores GC/scheduling spikes).
        var preprocessSamples: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = preprocess(raw)
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start
            preprocessSamples.append(Double(elapsedNs) / 1_000_000)
        }
        preprocessSamples.sort()
        let preprocessMs = preprocessSamples[preprocessSamples.count / 2]

        // Parse: median of 5 runs, on the fully preprocessed string (what
        // StructuredText actually receives).
        let rendered = preprocess(raw)
        var parseSamples: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try? parser.attributedString(for: rendered)
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start
            parseSamples.append(Double(elapsedNs) / 1_000_000)
        }
        parseSamples.sort()
        let parseMs = parseSamples[parseSamples.count / 2]

        // Web-view converter cost: this is the synchronous work the web-view
        // path does on the main thread today (Sources/WikiFS/SourceWebView.swift).
        // If large, it's the blocker async loading must move off-main.
        var convertSamples: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = MarkdownToHTML.convert(raw)
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start
            convertSamples.append(Double(elapsedNs) / 1_000_000)
        }
        convertSamples.sort()
        let convertMs = convertSamples[convertSamples.count / 2]

        // Sanity: the full pipeline produced a non-empty document.
        let attributed = try? parser.attributedString(for: rendered)
        #expect(attributed?.characters.isEmpty == false)

        let kb = Double(bytes) / 1024.0
        print("""

        ── reader render-path benchmark ─────────────────────────
        source size : \(bytes) bytes (\(String(format: "%.0f", kb)) KB)
        preprocess  : \(String(format: "%.1f", preprocessMs)) ms  (footnote expand + wiki-link linkify, full string)
        parse       : \(String(format: "%.1f", parseMs)) ms  (Textual Markdown → AttributedString)
        web convert : \(String(format: "%.1f", convertMs)) ms  (MarkdownToHTML → HTML string, web-view path)
        ──────────────────────────────────────────────────────────
        """)
    }

    // MARK: - Helpers

    /// Deterministic markdown shaped like a pdf2md extraction: headings,
    /// paragraphs with inline `[[wiki links]]`, and footnote refs + definitions.
    /// Footnote labels are globally unique so `WikiFootnoteMarkdown.rendered`
    /// renumbering is unambiguous across the whole document.
    private static func makeLargeMarkdown(targetBytes: Int) -> String {
        var output = ""
        var section = 0
        while output.utf8.count < targetBytes {
            section += 1
            output += "# Section \(section) — Overview\n\n"
            for p in 0..<4 {
                output += "This is paragraph \(p) of section \(section). "
                output += "It references [[Page \(p)]] and [[source:Paper \(section)]] inline, "
                output += "and cites a result[^f-\(section)-\(p)]. "
                output += String(repeating: "Filler prose to pad the block to a realistic length. ", count: 8)
                output += "\n\n"
            }
            for p in 0..<4 {
                output += "[^f-\(section)-\(p)]: Footnote definition \(p) for section \(section).\n"
            }
            output += "\n"
        }
        return output
    }
}
