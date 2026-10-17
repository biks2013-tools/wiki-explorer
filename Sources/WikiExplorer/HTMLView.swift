import SwiftUI
import WebKit

/// Renders a page or answer body (sanitised HTML from llm-wiki) in a WebKit view with JavaScript off.
/// Every link click is handed to `onLink` instead of navigating the view.
struct HTMLView: NSViewRepresentable {
    let html: String
    /// Folder relative image paths resolve against (the wiki root).
    let baseURL: URL?
    let onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLink: onLink) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
        let document = HTMLView.document(body: html)
        if context.coordinator.loaded != document {
            context.coordinator.loaded = document
            // Loaded from a file (not a string) so WebKit may read the page's local images: llm-wiki rewrites
            // image paths to absolute file:// URLs inside the wiki, and read access is granted from /.
            let file = context.coordinator.documentFile
            do {
                try document.write(to: file, atomically: true, encoding: .utf8)
                view.loadFileURL(file, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            } catch {
                view.loadHTMLString(document, baseURL: baseURL)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLink: (URL) -> Void
        var loaded: String?
        /// A private file per view, removed when the view goes away.
        let documentFile: URL = {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WikiExplorer", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("view-\(UUID().uuidString).html")
        }()

        deinit { try? FileManager.default.removeItem(at: documentFile) }

        init(onLink: @escaping (URL) -> Void) { self.onLink = onLink }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                decisionHandler(.cancel)
                if url.scheme == "about" { return } // in-page anchors
                onLink(url)
                return
            }
            decisionHandler(.allow)
        }
    }

    /// Wraps a body fragment in a document with the app's reading style (light and dark).
    static func document(body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data: https:; style-src 'unsafe-inline'">
        <style>\(css)</style></head><body><article>\(body)</article></body></html>
        """
    }

    static let css = """
    :root { color-scheme: light dark; --fg:#1d1f23; --muted:#646a73; --rule:#dcd8cf; --accent:#9a4a26; --code:rgba(0,0,0,.05); }
    @media (prefers-color-scheme: dark) { :root { --fg:#e6e4df; --muted:#9aa0a8; --rule:#3a3d42; --accent:#e08a5e; --code:rgba(255,255,255,.07); } }
    html,body { background: transparent; }
    body { margin:0; color:var(--fg); font: 15px/1.6 -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif; }
    article { max-width: 760px; margin: 0 auto; padding: 8px 28px 48px; }
    h1 { font-size: 1.9em; line-height:1.2; margin: .4em 0 .5em; }
    h2 { font-size: 1.35em; margin: 1.5em 0 .5em; } h3 { font-size: 1.12em; margin: 1.3em 0 .4em; }
    a { color: var(--accent); text-decoration: none; border-bottom: 1px solid color-mix(in srgb, var(--accent) 35%, transparent); }
    a:hover { border-bottom-color: var(--accent); }
    a.wikilink-missing, a[data-missing], span.wikilink-missing { color: var(--muted); border-bottom: 1px dashed var(--muted); }
    blockquote { margin: 1em 0; padding: .1em 1em; border-left: 3px solid var(--accent); color: var(--muted); }
    code, pre { font: 12.5px/1.5 ui-monospace, "SF Mono", Menlo, monospace; background: var(--code); border-radius: 5px; }
    code { padding: .1em .35em; } pre { padding: 10px 12px; overflow-x: auto; } pre code { background: none; padding: 0; }
    table { border-collapse: collapse; margin: 1em 0; font-size: .93em; display:block; overflow-x:auto; }
    th, td { border: 1px solid var(--rule); padding: 5px 9px; text-align: left; vertical-align: top; }
    th { background: var(--code); }
    img { max-width: 100%; }
    hr { border: none; border-top: 1px solid var(--rule); }
    """
}
