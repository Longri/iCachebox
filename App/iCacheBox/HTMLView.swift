import SwiftUI
import WebKit

/// Shows a cache description (HTML from the GPX file). JavaScript is off; links open in Safari.
/// The view grows with its content so that it can sit inside a ScrollView.
struct HTMLView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        context.coordinator.height = $height
        view.loadHTMLString(Self.page(html), baseURL: URL(string: "https://www.geocaching.com/"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Wraps the description into a page that follows the system font, size and dark mode.
    static func page(_ body: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
        body { font: -apple-system-body; margin: 0; padding: 0; word-wrap: break-word; color: CanvasText; }
        img, table { max-width: 100% !important; height: auto; }
        hr { border: none; border-top: 1px solid rgba(128, 128, 128, 0.35); margin: 1em 0; }
        a { color: #3d7a21; }
        @media (prefers-color-scheme: dark) { a { color: #5fa83a; } }
        </style></head><body>\(body)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        var height: Binding<CGFloat>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] value, _ in
                if let value = value as? CGFloat { self?.height?.wrappedValue = value }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

extension String {
    /// Plain text as HTML (escaped, line breaks kept) – Cachebox replaces line breaks by `<br />` the same way.
    var htmlEscapedParagraphs: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
