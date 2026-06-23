import SwiftUI
import WebKit
import WikiFSCore

// MARK: - SourceWebView

/// EXPERIMENTAL prototype: renders a source's markdown in a `WKWebView` instead
/// of the native `MarkdownPreview` (Textual), to test whether a browser engine's
/// windowed layout removes the ~10 s render freeze on 500 KB+ sources.
///
/// Loads **asynchronously**: the page chrome appears immediately with a loading
/// spinner, and the markdown→HTML conversion runs off the main actor (it's pure
/// string work — ~50 ms on 500 KB, see `ReaderRenderPerfTests`). The HTML is
/// handed to `WKWebView` once ready. Unlike the native reader, there is no
/// selection-overlay geometry constraint here, so deferring the load is safe.
///
/// Gated behind `@AppStorage("debug.webReader")` in `SourceDetailView` as an A/B
/// toggle against the native reader. Phase timings are logged under the render
/// category (`com.selfdrivingwiki.debug`) so the appear→convert→painted timeline
/// can be read back — the convert is cheap, so if the doc is still slow to paint
/// the cost is WKWebView cold-start / first-load, not conversion.
struct SourceWebView: View {
    let markdown: String
    var pendingAnchor: String? = nil
    let store: WikiStoreModel
    @State private var isLoading = true

    var body: some View {
        ZStack {
            WebViewRep(markdown: markdown,
                       pendingAnchor: pendingAnchor,
                       store: store,
                       isLoading: $isLoading)
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    /// Full HTML document string built around `body` (the converted markdown).
    /// Pure / callable off the main actor.
    nonisolated static func documentHTML(_ body: String) -> String {
        """
        <!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
          body {
            font: -apple-system-body; font-size: 15px; line-height: 1.55;
            max-width: 720px; margin: 24px auto 64px; padding: 0 24px;
            -webkit-text-size-adjust: 100%;
          }
          pre {
            background: rgba(128,128,128,0.14); padding: 12px 14px;
            border-radius: 8px; overflow: auto; font-size: 13px;
          }
          code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          a { color: -webkit-link; }
          h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 0.5em; }
          h1 { font-size: 1.7em; } h2 { font-size: 1.4em; } h3 { font-size: 1.15em; }
          ul, ol { padding-left: 1.6em; }
        </style></head>
        <body><article>\(body)</article></body></html>
        """
    }

    fileprivate static func scrollTo(_ anchor: String, in webView: WKWebView) {
        let id = anchor.replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript(
            "var e=document.getElementById(\"\(id)\"); if(e){e.scrollIntoView(true);}"
        )
    }
}

// MARK: - WKWebView bridge

private struct WebViewRep: NSViewRepresentable {
    let markdown: String
    let pendingAnchor: String?
    let store: WikiStoreModel
    @Binding var isLoading: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.store = store
        context.coordinator.startLoad(markdown: markdown, anchor: pendingAnchor, isLoading: $isLoading)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.store = store
        if context.coordinator.loadedMarkdown != markdown {
            context.coordinator.startLoad(markdown: markdown, anchor: pendingAnchor, isLoading: $isLoading)
        } else if let anchor = pendingAnchor, anchor != context.coordinator.scrolledAnchor {
            SourceWebView.scrollTo(anchor, in: webView)
            context.coordinator.scrolledAnchor = anchor
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var store: WikiStoreModel?
        var loadedMarkdown: String?
        var scrolledAnchor: String?
        private var pendingAnchorAfterLoad: String?
        private var convertTask: Task<Void, Never>?
        private var loadStart: DispatchTime?

        func startLoad(markdown: String, anchor: String?, isLoading: Binding<Bool>) {
            convertTask?.cancel()  // drop any in-flight conversion for stale markdown
            loadedMarkdown = markdown
            pendingAnchorAfterLoad = anchor
            scrolledAnchor = nil
            isLoadingBinding = isLoading   // held so didFinish can clear it
            isLoading.wrappedValue = true
            loadStart = DispatchTime.now()

            convertTask = Task.detached(priority: .userInitiated) { [weak self] in
                let t0 = DispatchTime.now()
                let body = MarkdownToHTML.convert(markdown)
                let html = SourceWebView.documentHTML(body)
                let convertMs = Self.elapsedMs(since: t0)
                await MainActor.run { [weak self] in
                    guard let self, let webView = self.webView,
                          self.loadedMarkdown == markdown else { return }
                    ReaderTiming.point("webview.convert", ms: convertMs)
                    webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let start = loadStart {
                ReaderTiming.point("webview.appear-to-painted", ms: Self.elapsedMs(since: start))
            }
            isLoadingBinding?.wrappedValue = false
            if let anchor = pendingAnchorAfterLoad {
                SourceWebView.scrollTo(anchor, in: webView)
                scrolledAnchor = anchor
            }
        }

        // The loading binding is held here so didFinish can clear it (the call
        // happens later, outside startLoad); refreshed on each startLoad.
        private var isLoadingBinding: Binding<Bool>?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url, url.scheme == "wiki" {
                route(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func route(_ url: URL) {
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            let kind = comps.host ?? ""
            var target = comps.path
            if target.hasPrefix("/") { target.removeFirst() }
            target = target.removingPercentEncoding ?? target
            let frag = comps.fragment
            switch kind {
            case "page":   store?.selectPage(byTitle: target, anchor: frag)
            case "source": store?.selectSource(byDisplayName: target, anchor: frag)
            default: break
            }
        }

        nonisolated private static func elapsedMs(since start: DispatchTime) -> Double {
            Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        }
    }
}

// MARK: - Minimal Markdown → HTML

/// A deliberately small Markdown→HTML converter for the web-view reader
/// prototype. Produces headings with GFM-style `id` slugs (so `#fragment` anchor
/// scrolling works the same as the native reader), paragraphs, unordered/ordered
/// lists, fenced code blocks, inline bold/italic/code, and both wiki links
/// (`[[Page]]`, `[[source:Name]]`, `[[Page#frag]]`, `[[Page|Alias]]`) and regular
/// `[text](url)` links. Footnotes and tables fall through as plain text — the
/// goal is to test browser layout/scroll perf and link/anchor routing, not full
/// GFM fidelity. Pure/thread-safe: called off the main actor.
enum MarkdownToHTML {

    static func convert(_ markdown: String) -> String {
        var output: [String] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var slugCounts: [String: Int] = [:]

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(escape(lines[i]))
                    i += 1
                }
                if i < lines.count { i += 1 }  // consume closing fence
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                output.append("<pre><code\(cls)>\(code.joined(separator: "\n"))</code></pre>")
                continue
            }

            // Heading.
            if let level = headingLevel(trimmed) {
                let text = trimmed.drop { $0 == "#" }.drop(while: { $0.isWhitespace })
                let slug = makeSlug(String(text), counts: &slugCounts)
                output.append("<h\(level) id=\"\(escape(slug))\">\(inline(String(text)))</h\(level)>")
                i += 1
                continue
            }

            // Unordered list.
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count, isUnorderedItem(lines[i]) {
                    let body = lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)
                    items.append("<li>\(inline(String(body)))</li>")
                    i += 1
                }
                output.append("<ul>\(items.joined())</ul>")
                continue
            }

            // Ordered list.
            if isOrderedItem(trimmed) {
                var items: [String] = []
                while i < lines.count, isOrderedItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let body = lines[i].trimmingCharacters(in: .whitespaces)
                    let rest = body.range(of: #"^\d+\.\s"#, options: .regularExpression)
                        .map { String(body[$0.upperBound...]) } ?? body
                    items.append("<li>\(inline(rest))</li>")
                    i += 1
                }
                output.append("<ol>\(items.joined())</ol>")
                continue
            }

            // Paragraph: gather until a blank line or a block-starting line.
            var para: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("```") || headingLevel(t) != nil
                    || t.hasPrefix("- ") || t.hasPrefix("* ") || isOrderedItem(t) { break }
                para.append(lines[i])
                i += 1
            }
            if !para.isEmpty {
                output.append("<p>\(inline(para.joined(separator: " ")))</p>")
            }
        }
        return output.joined(separator: "\n")
    }

    // MARK: Inline

    private static func inline(_ raw: String) -> String {
        var s = escape(raw)
        s = replace(s, pattern: #"\[\[([^\]]+)\]\]"#) { groups in wikiLink(groups[1]) }
        s = replace(s, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) { groups in
            "<a href=\"\(escape(groups[2]))\">\(groups[1])</a>"
        }
        s = replace(s, pattern: #"`([^`]+)`"#) { groups in "<code>\(groups[1])</code>" }
        s = replace(s, pattern: #"\*\*([^*]+)\*\*"#) { groups in "<strong>\(groups[1])</strong>" }
        s = replace(s, pattern: #"\*([^*]+)\*"#) { groups in "<em>\(groups[1])</em>" }
        return s
    }

    /// Render a `[[…]]` inner payload as a `<a>`. Handles `source:` prefix,
    /// `#fragment`, and `target|alias`. Routes page links to `wiki://page/…` and
    /// source links to `wiki://source/…`, which the navigation delegate routes.
    private static func wikiLink(_ inner: String) -> String {
        let parts = inner.split(separator: "|", maxSplits: 1)
        let target = String(parts.first ?? "")
        let alias = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil
        var body = target
        var fragment: String?
        if let hash = body.firstIndex(of: "#") {
            fragment = String(body[body.index(after: hash)...])
            body = String(body[body.startIndex..<hash])
        }
        let kind: String
        let titleForDisplay: String
        if body.hasPrefix("source:") {
            kind = "source"
            titleForDisplay = String(body.dropFirst("source:".count))
        } else {
            kind = "page"
            titleForDisplay = body
        }
        let display = alias ?? titleForDisplay
        var href = "wiki://\(kind)/\(encoded(titleForDisplay))"
        if let fragment { href += "#\(encoded(fragment))" }
        return "<a href=\"\(href)\">\(escape(display))</a>"
    }

    // MARK: Block helpers

    private static func headingLevel(_ line: String) -> Int? {
        var n = 0
        for ch in line { if ch == "#", n < 6 { n += 1 } else { break } }
        guard n > 0, line.count > n, line[line.index(line.startIndex, offsetBy: n)] == " " else { return nil }
        return n
    }

    private static func isUnorderedItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("- ") || t.hasPrefix("* ")
    }

    private static func isOrderedItem(_ line: String) -> Bool {
        line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    // MARK: Slug (mirrors AnchorBlock.makeSlug so fragments resolve identically)

    private static func makeSlug(_ text: String, counts: inout [String: Int]) -> String {
        let base = String(
            text
                .lowercased()
                .map { $0.isWhitespace ? "-" : $0 }
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                .split(separator: "-", omittingEmptySubsequences: true)
                .joined(separator: "-")
        )
        guard !base.isEmpty else { return "heading" }
        let count = counts[base, default: 0]
        counts[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }

    // MARK: String helpers

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func encoded(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    /// Regex replace with capture groups passed as `[full, g1, g2, …]`.
    private static func replace(_ s: String, pattern: String,
                                using build: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out = ""
        var cursor = 0
        for match in matches {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            var groups = [ns.substring(with: match.range)]
            for g in 1..<match.numberOfRanges {
                let r = match.range(at: g)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            out += build(groups)
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }
}
