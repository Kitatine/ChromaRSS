#if os(macOS)
import AppKit
import Network
import os
import SwiftData
import SwiftUI
import WebKit

@MainActor
final class LoopbackArticleServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    func start() async throws -> URL {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        let html = Self.articleHTML
        let payload = Data(html.utf8)

        listener.newConnectionHandler = { conn in
            conn.start(queue: .global(qos: .userInitiated))
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { _, _, _, _ in
                let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                var response = Data(header.utf8)
                response.append(payload)
                conn.send(content: response, completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }

        let boundPort: UInt16 = try await withCheckedThrowingContinuation { cont in
            let done = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let shouldResume = done.withLock { flag -> Bool in
                        if flag { return false }
                        flag = true
                        return true
                    }
                    if shouldResume { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let err):
                    let shouldResume = done.withLock { flag -> Bool in
                        if flag { return false }
                        flag = true
                        return true
                    }
                    if shouldResume { cont.resume(throwing: err) }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
        self.port = boundPort
        return URL(string: "http://127.0.0.1:\(boundPort)/article")!
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    static let articleHTML = """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Zenn: iOS RSS Reader with Chrome Extensions</title>
      <style>
        body { font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif; margin: 0; padding: 20px; color: #1c1c1e; background: #ffffff; }
        .tag { display: inline-block; font-size: 12px; font-weight: 600; color: #0a84ff; background: rgba(10,132,255,0.12); padding: 3px 9px; border-radius: 999px; margin-bottom: 10px; }
        h1 { font-size: 22px; line-height: 1.3; margin: 0 0 8px; }
        .meta { color: #6e6e73; font-size: 13px; margin-bottom: 18px; }
        p { margin: 0 0 14px; }
        blockquote { margin: 14px 0; padding: 10px 14px; background: #f5f5f7; border-radius: 10px; color: #3a3a3c; }
      </style>
    </head>
    <body>
      <span class="tag">Zenn · Tech</span>
      <h1>iOS 18.4 の WKWebExtension で Chrome 拡張機能を RSS リーダーに組み込む</h1>
      <div class="meta">kitawu · 3 min read · zenn.dev</div>
      <p>これまで iOS で RSS 記事を翻訳拡張機能（Immersive Translate など）と一緒に読むには、一度外部ブラウザへ切り替える必要がありました。</p>
      <p>iOS 18.4 で追加された WKWebExtensionController を使うと、アプリ内の WKWebView 上で Chrome 拡張機能のコンテンツスクリプトやポップアップをそのまま実行できます。</p>
      <blockquote>Chrome Web Store の .crx / .zip パッケージを展開し、記事ごとにシームレスなバイリンガル閲覧体験を実現します。</blockquote>
      <p>With ChromaRSS, every feed item opens directly inside an extension-capable browser tab—keeping your translation overlays, popups, and settings in one place.</p>
    </body>
    </html>
    """
}

struct ScreenshotHarnessView: View {
    let outputDir: String

    @Environment(\.modelContext) private var modelContext
    @Environment(ExtensionManager.self) private var manager

    enum Screen {
        case feeds
        case browser(BrowserTarget)
        case extensions
    }

    @State private var screen: Screen = .feeds
    @State private var hasRun = false
    @State private var server = LoopbackArticleServer()
    @State private var hostWindow: NSWindow?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            switch screen {
            case .feeds:
                NavigationStack {
                    ArticleListView(scope: .all, title: "Unread · ChromaRSS")
                }
            case .browser(let target):
                ExtensionBrowserView(target: target)
            case .extensions:
                ExtensionManagerView()
            }
        }
        .frame(width: 430, height: 880)
        .background(WindowFinder { win in
            if hostWindow !== win {
                hostWindow = win
                configureWindow(win)
            }
        })
        .task {
            guard !hasRun else { return }
            hasRun = true
            await runCapturePipeline()
        }
    }

    private func configureWindow(_ win: NSWindow) {
        win.appearance = NSAppearance(named: .aqua)
        win.setContentSize(NSSize(width: 430, height: 880))
        win.styleMask.remove(.resizable)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func runCapturePipeline() async {
        do {
            let outURL = URL(fileURLWithPath: outputDir, isDirectory: true)
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

            await manager.bootstrap()
            seedSampleData()
            let articleURL = try await server.start()

            // Wait for initial window layout
            try await Task.sleep(for: .milliseconds(900))
            if let win = hostWindow {
                configureWindow(win)
            }
            try await Task.sleep(for: .milliseconds(400))

            // 1. Feeds / Articles screen
            let feedsImg = captureWindow(webView: nil)
            savePNG(feedsImg, to: outURL.appendingPathComponent("01-feeds.png"))

            // 2. Extension Browser screen with active extension injection
            let sampleArticle = (try? modelContext.fetch(FetchDescriptor<Article>()))?.first
            let target = BrowserTarget(url: articleURL, title: "iOS 18.4 WKWebExtension Guide", article: sampleArticle)
            screen = .browser(target)

            // Wait until active WKWebView finishes loading and content script injects
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(250))
                if let tab = manager.activeSession?.activeTab, !tab.isLoading, tab.url != nil {
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(900))

            if let wv = manager.activeSession?.activeTab?.webView {
                _ = try? await wv.evaluateJavaScript("""
                    (() => {
                      const pill = document.querySelector('.chroma-pill');
                      if (pill) pill.click();
                      const firstP = document.querySelector('p');
                      if (firstP) firstP.click();
                      return document.querySelectorAll('.chroma-callout').length;
                    })();
                """)
                try await Task.sleep(for: .milliseconds(500))
            }

            let browserImg = await captureWindowWithWebView(manager.activeSession?.activeTab?.webView)
            savePNG(browserImg, to: outURL.appendingPathComponent("02-extension-browser.png"))

            // 3. Extensions manager screen
            screen = .extensions
            try await Task.sleep(for: .milliseconds(700))
            let extImg = captureWindow(webView: nil)
            savePNG(extImg, to: outURL.appendingPathComponent("03-extension-manager.png"))

            // 4. Composite 3-up showcase
            if let f = feedsImg, let b = browserImg, let e = extImg {
                let composite = makeShowcase(images: [f, b, e])
                savePNG(composite, to: outURL.appendingPathComponent("showcase.png"))
            }

            server.stop()
        } catch {
            fputs("Screenshot capture failed: \(error)\n", stderr)
            server.stop()
        }
        try? await Task.sleep(for: .milliseconds(200))
        NSApplication.shared.terminate(nil)
    }

    private func seedSampleData() {
        let now = Date()
        let tech = Feed(feedURL: "https://simonwillison.net/atom/everything/", title: "Simon Willison's Weblog", folderName: "Tech")
        let zenn = Feed(feedURL: "https://zenn.dev/feed", title: "Zenn (日本語)", folderName: "Foreign Language")
        let hn = Feed(feedURL: "https://hnrss.org/frontpage", title: "Hacker News", folderName: "Tech")
        let lm = Feed(feedURL: "https://www.lemonde.fr/rss/une.xml", title: "Le Monde (Français)", folderName: "Foreign Language")
        [zenn, tech, hn, lm].forEach { modelContext.insert($0) }

        let samples: [(Feed, String, String, String, TimeInterval)] = [
            (zenn, "iOS 18.4 の WKWebExtension で Chrome 拡張機能を RSS リーダーに組み込む",
             "WKWebExtensionController を使ってアプリ内ブラウザで翻訳拡張機能をそのまま動かす手法を紹介します。",
             "https://zenn.dev/articles/wkwebextension-rss", -900),
            (tech, "Running Real WebExtensions Inside WKWebView on iOS 18.4",
             "Apple's new WKWebExtension APIs allow native apps to load unpacked Manifest V3 extensions with persistent chrome.storage.",
             "https://simonwillison.net/2025/wkwebextension", -3600),
            (lm, "L'intelligence artificielle transforme la lecture d'actualités multilingues sur mobile",
             "Comment les extensions de traduction bilingue facilitent la veille internationale au quotidien.",
             "https://www.lemonde.fr/pixels/article", -7200),
            (hn, "Show HN: ChromaRSS — iOS RSS Reader with In-App Chrome Extensions",
             "Open articles directly in an extension-ready WKWebView so Immersive Translate works natively.",
             "https://news.ycombinator.com/item?id=1", -14400),
            (zenn, "Swift 6 Strict Concurrency と SwiftData 実践パターン",
             "Observable マクロと MainActor 分離を使ったモダンな iOS アプリ設計。",
             "https://zenn.dev/articles/swift6-swiftdata", -21600)
        ]

        for (i, item) in samples.enumerated() {
            let a = Article(
                feedURL: item.0.feedURL,
                guid: "sample-\(i)",
                title: item.1,
                link: item.3,
                author: item.0.title,
                summary: item.2,
                publishedAt: now.addingTimeInterval(item.4)
            )
            a.isStarred = (i == 0 || i == 2)
            a.isRead = (i == 4)
            a.feed = item.0
            modelContext.insert(a)
        }
        try? modelContext.save()
    }

    private func captureWindow(webView: WKWebView?) -> NSImage? {
        guard let win = hostWindow, let contentView = win.contentView else { return nil }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        contentView.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func captureWindowWithWebView(_ webView: WKWebView?) async -> NSImage? {
        guard let win = hostWindow, let contentView = win.contentView else { return nil }
        let base = captureWindow(webView: nil)
        guard let base, let webView else { return base }

        let snapConfig = WKSnapshotConfiguration()
        guard let webSnap = try? await webView.takeSnapshot(configuration: snapConfig) else { return base }

        // Convert webView rect into contentView coordinates; flip Y for NSImage drawing (origin bottom-left).
        let rectInContent = webView.convert(webView.bounds, to: contentView)
        let drawRect = NSRect(
            x: rectInContent.minX,
            y: contentView.isFlipped ? (contentView.bounds.height - rectInContent.maxY) : rectInContent.minY,
            width: rectInContent.width,
            height: rectInContent.height
        )

        let scale = win.backingScaleFactor
        let pixelW = Int(contentView.bounds.width * scale)
        let pixelH = Int(contentView.bounds.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelW, pixelsHigh: pixelH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return base }
        rep.size = contentView.bounds.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        base.draw(in: NSRect(origin: .zero, size: contentView.bounds.size))
        webSnap.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: contentView.bounds.size)
        out.addRepresentation(rep)
        return out
    }

    private func savePNG(_ image: NSImage?, to url: URL) {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private func makeShowcase(images: [NSImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }
        let pad: CGFloat = 28
        let gap: CGFloat = 24
        let cardW: CGFloat = 430
        let cardH: CGFloat = 880
        let totalW = pad * 2 + cardW * CGFloat(images.count) + gap * CGFloat(images.count - 1)
        let totalH = pad * 2 + cardH
        let scale: CGFloat = 2

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(totalW * scale), pixelsHigh: Int(totalH * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: totalW, height: totalH)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        NSColor(calibratedRed: 0.945, green: 0.955, blue: 0.97, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: totalW, height: totalH)).fill()

        for (idx, img) in images.enumerated() {
            let x = pad + CGFloat(idx) * (cardW + gap)
            let rect = NSRect(x: x, y: pad, width: cardW, height: cardH)
            let path = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            img.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: totalW, height: totalH))
        out.addRepresentation(rep)
        return out
    }
}

private struct WindowFinder: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window { onWindow(w) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { onWindow(w) }
        }
    }
}
#endif
