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
                // Shared pre-pass (footnotes + wiki links) + swift-markdown HTML
                // render, both off the main actor. isResolved is constant here —
                // the web reader can't call the @MainActor store from this task,
                // so ghost-link coloring is a follow-up.
                let prepared = ReaderMarkdown.prepared(markdown) { _, _ in true }
                let body = MarkdownHTMLRenderer.render(prepared)
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
