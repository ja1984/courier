import AppKit
import SwiftUI
import WebKit

/// Renders an HTML response. JavaScript is off and no cookies or storage persist,
/// so previewing an arbitrary page can't act on your behalf. Links open in the default browser.
struct HTMLPreview: NSViewRepresentable {
    struct FindRequest: Equatable {
        var id = 0
        var query = ""
        var backwards = false
    }

    let html: String
    let baseURL: URL?
    /// Each new request id runs WebKit's find once; the result reports whether anything matched.
    var find = FindRequest()
    var onFindResult: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setAccessibilityLabel("Rendered HTML preview")
        load(into: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedHTML != html || context.coordinator.loadedBaseURL != baseURL {
            load(into: webView, context: context)
        }
        if find.id != context.coordinator.lastFindID {
            context.coordinator.lastFindID = find.id
            guard !find.query.isEmpty else { return }
            let configuration = WKFindConfiguration()
            configuration.backwards = find.backwards
            configuration.caseSensitive = false
            configuration.wraps = true
            let report = onFindResult
            webView.find(find.query, configuration: configuration) { result in
                report(result.matchFound)
            }
        }
    }

    private func load(into webView: WKWebView, context: Context) {
        context.coordinator.loadedHTML = html
        context.coordinator.loadedBaseURL = baseURL
        // The base URL lets relative stylesheets and images resolve against the server.
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var loadedBaseURL: URL?
        var lastFindID = 0

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
