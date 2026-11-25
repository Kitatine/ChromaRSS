import SwiftUI
import WebKit

#if os(iOS)
/// Hosts a tab's `WKWebView`, swapping the subview if the tab replaces its web view.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        attach(webView, to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if container.subviews.first !== webView {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(webView, to: container)
        }
    }

    private func attach(_ wv: WKWebView, to container: UIView) {
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

/// Loads an extension-internal page (options, etc.) using the extension's own configuration.
struct ExtensionPageWebView: UIViewRepresentable {
    let extensionContext: WKWebExtensionContext

    func makeUIView(context: Context) -> WKWebView {
        let config = extensionContext.webViewConfiguration ?? WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isInspectable = true
        if let url = extensionContext.optionsPageURL { wv.load(URLRequest(url: url)) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
/// Hosts a tab's `WKWebView`, swapping the subview if the tab replaces its web view.
struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(webView, to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if container.subviews.first !== webView {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(webView, to: container)
        }
    }

    private func attach(_ wv: WKWebView, to container: NSView) {
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

/// Loads an extension-internal page (options, etc.) using the extension's own configuration.
struct ExtensionPageWebView: NSViewRepresentable {
    let extensionContext: WKWebExtensionContext

    func makeNSView(context: Context) -> WKWebView {
        let config = extensionContext.webViewConfiguration ?? WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isInspectable = true
        if let url = extensionContext.optionsPageURL { wv.load(URLRequest(url: url)) }
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
