import SwiftUI
import WebKit

/// Renders an artifact in a non-persistent WebKit instance with no native message bridge.
/// A restrictive CSP is inserted before artifact content; navigation stays in this view unless
/// the user approves an HTTP(S) link in the native confirmation dialog.
struct ArtifactWebSandboxView: View {
    let html: String
    @Environment(\.openURL) private var openURL
    @State private var externalURL: URL?

    var body: some View {
        Group {
        #if os(iOS)
        IOSArtifactWebView(html: html) { externalURL = $0 }
        #elseif os(macOS)
        MacArtifactWebView(html: html) { externalURL = $0 }
        #else
        Text("此设备不支持网页构件。")
        #endif
        }
        .alert("在浏览器打开链接？", isPresented: Binding(
            get: { externalURL != nil },
            set: { if !$0 { externalURL = nil } }
        )) {
            Button("打开") {
                if let externalURL { openURL(externalURL) }
                externalURL = nil
            }
            Button("取消", role: .cancel) { externalURL = nil }
        } message: {
            Text(externalURL?.host.map { "将打开 \($0)。请确认网址和页面。" } ?? "将交给系统浏览器打开此链接。")
        }
    }
}

enum ArtifactWebSandbox {
    static func approvedExternalURL(from navigationAction: WKNavigationAction) -> URL? {
        guard navigationAction.navigationType == .linkActivated else { return nil }
        return validatedExternalURL(navigationAction.request.url)
    }

    static func validatedExternalURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func wrappedHTML(_ html: String) -> String {
        let securityHeaders = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=3">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob:; media-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:; frame-src 'none'; connect-src 'none'; form-action 'none'; object-src 'none'; base-uri 'none';">
        <style>html,body{margin:0;min-height:100%;background:#111;color:#f4f4f7}</style>
        """
        if let head = html.range(of: "<head", options: .caseInsensitive),
           let tagEnd = html[head.upperBound...].firstIndex(of: ">") {
            var document = html
            document.insert(contentsOf: securityHeaders, at: tagEnd < document.endIndex ? document.index(after: tagEnd) : tagEnd)
            return document
        }
        if let htmlTag = html.range(of: "<html", options: .caseInsensitive),
           let tagEnd = html[htmlTag.upperBound...].firstIndex(of: ">") {
            var document = html
            let insertion = document.index(after: tagEnd)
            document.insert(contentsOf: "<head>\(securityHeaders)</head>", at: insertion)
            return document
        }
        return "<!doctype html><html lang=\"zh-CN\"><head>\(securityHeaders)</head><body>\(html)</body></html>"
    }

    fileprivate static func makeWebView(delegate: ArtifactWebViewCoordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        return webView
    }
}

fileprivate class ArtifactWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var permitsNextInMemoryLoad = false
    private let onExternalLink: (URL) -> Void

    init(onExternalLink: @escaping (URL) -> Void) {
        self.onExternalLink = onExternalLink
        super.init()
    }

    func authorizeNextInMemoryLoad() { permitsNextInMemoryLoad = true }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow only loadHTMLString's one-shot about:blank navigation; page and link navigation are blocked.
        let mayLoadMemoryDocument = permitsNextInMemoryLoad && navigationAction.request.url?.absoluteString == "about:blank"
        if mayLoadMemoryDocument { permitsNextInMemoryLoad = false }
        if let url = ArtifactWebSandbox.approvedExternalURL(from: navigationAction) { onExternalLink(url) }
        decisionHandler(mayLoadMemoryDocument ? .allow : .cancel)
    }
}

private extension ArtifactWebViewCoordinator {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = ArtifactWebSandbox.approvedExternalURL(from: navigationAction) { onExternalLink(url) }
        return nil
    }
}

#if os(iOS)
private struct IOSArtifactWebView: UIViewRepresentable {
    let html: String
    let onExternalLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExternalLink: onExternalLink) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = ArtifactWebSandbox.makeWebView(delegate: context.coordinator)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.load(html, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { context.coordinator.load(html, into: webView) }

    final class Coordinator: ArtifactWebViewCoordinator {
        private var loadedHTML: String?

        func load(_ html: String, into webView: WKWebView) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            authorizeNextInMemoryLoad()
            webView.loadHTMLString(ArtifactWebSandbox.wrappedHTML(html), baseURL: nil)
        }
    }
}
#elseif os(macOS)
private struct MacArtifactWebView: NSViewRepresentable {
    let html: String
    let onExternalLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExternalLink: onExternalLink) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = ArtifactWebSandbox.makeWebView(delegate: context.coordinator)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(html, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) { context.coordinator.load(html, into: webView) }

    final class Coordinator: ArtifactWebViewCoordinator {
        private var loadedHTML: String?

        func load(_ html: String, into webView: WKWebView) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            authorizeNextInMemoryLoad()
            webView.loadHTMLString(ArtifactWebSandbox.wrappedHTML(html), baseURL: nil)
        }
    }
}
#endif
