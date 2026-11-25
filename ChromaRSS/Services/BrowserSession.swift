import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import WebKit
import Observation

@MainActor
final class BrowserWindowAdapter: NSObject, WKWebExtensionWindow {
    weak var session: BrowserSession?

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { session?.tabs ?? [] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { session?.activeTab }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect {
        session?.activeTab?.webView.window?.frame ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }
    #if os(macOS)
    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
    #endif
    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) { completionHandler(nil) }
}

@MainActor
@Observable
final class BrowserTabAdapter: NSObject, WKWebExtensionTab, WKNavigationDelegate, WKUIDelegate, Identifiable {
    let id = UUID()
    @ObservationIgnored weak var session: BrowserSession?

    private(set) var webView: WKWebView
    private(set) var title: String = ""
    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isExtensionPage: Bool

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(session: BrowserSession, initialURL: URL?) {
        self.session = session
        let ext = initialURL?.scheme == "webkit-extension"
        self.isExtensionPage = ext
        self.webView = BrowserTabAdapter.makeWebView(session: session, forExtensionURL: initialURL)
        super.init()
        attach(webView)
        if let initialURL { webView.load(URLRequest(url: initialURL)) }
    }

    private static func makeWebView(session: BrowserSession, forExtensionURL url: URL?) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: session.makeConfiguration(for: url))
        wv.allowsBackForwardNavigationGestures = true
        wv.isInspectable = true
        #if os(iOS)
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        #endif
        return wv
    }

    private func attach(_ wv: WKWebView) {
        wv.navigationDelegate = self
        wv.uiDelegate = self
        observations = [
            wv.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.syncState() } },
            wv.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.syncState() } },
            wv.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.syncState() } },
            wv.observe(\.estimatedProgress) { [weak self] _, _ in Task { @MainActor in self?.syncState() } },
            wv.observe(\.canGoBack) { [weak self] _, _ in Task { @MainActor in self?.syncState() } },
            wv.observe(\.canGoForward) { [weak self] _, _ in Task { @MainActor in self?.syncState() } }
        ]
        syncState()
    }

    private func syncState() {
        var changed: WKWebExtension.TabChangedProperties = []
        let newTitle = webView.title ?? ""
        if newTitle != title { changed.insert(.title) }
        if webView.url != url { changed.insert(.URL) }
        if webView.isLoading != isLoading { changed.insert(.loading) }
        title = newTitle
        url = webView.url
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if !changed.isEmpty { session?.manager.controller.didChangeTabProperties(changed, for: self) }
    }

    // MARK: Loading

    func load(_ url: URL) {
        let wantsExtension = url.scheme == "webkit-extension"
        if wantsExtension != isExtensionPage, let session {
            // Extension pages need the extension's own web view configuration (and vice versa).
            observations = []
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
            webView = BrowserTabAdapter.makeWebView(session: session, forExtensionURL: url)
            isExtensionPage = wantsExtension
            attach(webView)
        }
        webView.load(URLRequest(url: url))
    }

    func stopOrReload() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        let scheme = (url.scheme ?? "").lowercased()
        let internalSchemes: Set<String> = ["http", "https", "about", "blob", "data", "file", "webkit-extension", "javascript"]
        if !internalSchemes.contains(scheme) {
            PlatformSupport.openExternalURL(url)
            return .cancel
        }
        let isMain = navigationAction.targetFrame?.isMainFrame ?? true
        if isMain, (scheme == "webkit-extension") != isExtensionPage, scheme != "about", scheme != "blob", scheme != "data" {
            load(url)
            return .cancel
        }
        return .allow
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.absoluteString != "about:blank" {
            session?.openTab(url: url, activate: true)
        }
        return nil
    }

    // MARK: WKWebExtensionTab

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { session?.window }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        session?.tabs.firstIndex(where: { $0 === self }) ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { webView.title }
    func url(for context: WKWebExtensionContext) -> URL? { webView.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { webView.reloadFromOrigin() } else { webView.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goForward()
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        session?.select(self)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        session?.close(self)
        completionHandler(nil)
    }
}

@MainActor
@Observable
final class BrowserSession {
    @ObservationIgnored let manager: ExtensionManager
    @ObservationIgnored let window = BrowserWindowAdapter()

    private(set) var tabs: [BrowserTabAdapter] = []
    private(set) var activeTabID: UUID?
    var shouldDismiss = false

    var activeTab: BrowserTabAdapter? { tabs.first { $0.id == activeTabID } }

    init(manager: ExtensionManager) {
        self.manager = manager
        window.session = self
    }

    func start(initialURL: URL) {
        manager.activeSession = self
        manager.controller.didOpenWindow(window)
        manager.controller.didFocusWindow(window)
        openTab(url: initialURL, activate: true)
    }

    func end() {
        for tab in tabs { manager.controller.didCloseTab(tab, windowIsClosing: true) }
        manager.controller.didCloseWindow(window)
        tabs.removeAll()
        activeTabID = nil
        if manager.activeSession === self { manager.activeSession = nil }
    }

    @discardableResult
    func openTab(url: URL?, activate: Bool) -> BrowserTabAdapter {
        let tab = BrowserTabAdapter(session: self, initialURL: url)
        tabs.append(tab)
        manager.controller.didOpenTab(tab)
        if activate || activeTabID == nil { select(tab) }
        return tab
    }

    func select(_ tab: BrowserTabAdapter) {
        let previous = activeTab
        guard previous !== tab else { return }
        activeTabID = tab.id
        manager.controller.didActivateTab(tab, previousActiveTab: previous)
    }

    func close(_ tab: BrowserTabAdapter) {
        guard let idx = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasActive = tab.id == activeTabID
        tabs.remove(at: idx)
        manager.controller.didCloseTab(tab, windowIsClosing: tabs.isEmpty)
        if tabs.isEmpty {
            activeTabID = nil
            shouldDismiss = true
        } else if wasActive {
            let next = tabs[min(idx, tabs.count - 1)]
            activeTabID = next.id
            manager.controller.didActivateTab(next, previousActiveTab: nil)
        }
    }

    func makeConfiguration(for url: URL?) -> WKWebViewConfiguration {
        if let url, url.scheme == "webkit-extension",
           let ctx = manager.controller.extensionContext(for: url),
           let cfg = ctx.webViewConfiguration {
            return cfg
        }
        let cfg = WKWebViewConfiguration()
        cfg.webExtensionController = manager.controller
        cfg.websiteDataStore = .default()
        #if os(iOS)
        cfg.allowsInlineMediaPlayback = true
        #endif
        cfg.applicationNameForUserAgent = "Version/18.4 Mobile/15E148 Safari/604.1"
        return cfg
    }
}
