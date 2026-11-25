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
        let htmlData = Data(Self.articleHTML.utf8)
        let thumb1 = Self.makeThumbPNG(top: NSColor(calibratedRed: 0.18, green: 0.27, blue: 0.74, alpha: 1),
                                        bottom: NSColor(calibratedRed: 0.32, green: 0.52, blue: 0.96, alpha: 1),
                                        badge: "WKWebKit")
        let thumb2 = Self.makeThumbPNG(top: NSColor(calibratedRed: 0.08, green: 0.53, blue: 0.62, alpha: 1),
                                        bottom: NSColor(calibratedRed: 0.16, green: 0.74, blue: 0.72, alpha: 1),
                                        badge: "Swift 6")

        listener.newConnectionHandler = { conn in
            conn.start(queue: .global(qos: .userInitiated))
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let req = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let firstLine = req.split(separator: "\r\n").first ?? ""
                let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/article"

                let contentType: String
                let body: Data
                if path.contains("thumb-1") {
                    contentType = "image/png"
                    body = thumb1
                } else if path.contains("thumb-2") {
                    contentType = "image/png"
                    body = thumb2
                } else {
                    contentType = "text/html; charset=utf-8"
                    body = htmlData
                }

                let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                var response = Data(header.utf8)
                response.append(body)
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

    private static func makeThumbPNG(top: NSColor, bottom: NSColor, badge: String) -> Data {
        let size = NSSize(width: 240, height: 180)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return Data() }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let grad = NSGradient(starting: top, ending: bottom)
        grad?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: 130, y: 80, width: 140, height: 140)).fill()
        NSBezierPath(ovalIn: NSRect(x: -30, y: -40, width: 120, height: 120)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: badge, attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: (size.width - strSize.width) / 2, y: (size.height - strSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    static let articleHTML = """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Zenn: iOS 18.4 WKWebExtension Guide</title>
      <style>
        body { font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif; margin: 0; padding: 20px; color: #1c1c1e; background: #ffffff; }
        .tag { display: inline-block; font-size: 12px; font-weight: 600; color: #3b5bdb; background: rgba(59,91,219,0.12); padding: 4px 10px; border-radius: 999px; margin-bottom: 10px; }
        h1 { font-size: 22px; line-height: 1.32; margin: 0 0 8px; }
        .meta { color: #6e6e73; font-size: 13px; margin-bottom: 18px; }
        p { margin: 0 0 14px; }
        blockquote { margin: 14px 0; padding: 12px 14px; background: #f4f6fb; border-radius: 12px; color: #2f3342; }
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
    @Environment(AppSettings.self) private var settings

    enum Screen {
        case stream
        case library
        case browser(BrowserTarget)
        case extensions
        case workspace(Article?)
    }

    @State private var screen: Screen = .stream
    @State private var hasRun = false
    @State private var server = LoopbackArticleServer()
    @State private var hostWindow: NSWindow?
    @State private var targetSize = NSSize(width: 430, height: 880)

    var body: some View {
        ZStack {
            settings.readerTheme.canvasColor.ignoresSafeArea()
            switch screen {
            case .stream:
                NavigationStack {
                    ArticleListView(scope: .all, title: "ChromaRSS")
                }
            case .library:
                FeedsListView()
            case .browser(let target):
                ExtensionBrowserView(target: target)
            case .extensions:
                ExtensionManagerView()
            case .workspace(let article):
                InoreaderWorkspaceView(initialSelectedArticle: article)
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .background(WindowFinder { win in
            if hostWindow !== win {
                hostWindow = win
                configureWindow(win, size: targetSize)
            }
        })
        .task {
            guard !hasRun else { return }
            hasRun = true
            await runCapturePipeline()
        }
    }

    private func configureWindow(_ win: NSWindow, size: NSSize) {
        win.appearance = NSAppearance(named: .aqua)
        win.setContentSize(size)
        win.styleMask.remove(.resizable)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func runCapturePipeline() async {
        do {
            let outURL = URL(fileURLWithPath: outputDir, isDirectory: true)
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

            settings.readerTheme = .light
            settings.streamLayout = .magazine
            settings.headlineDesign = .serif
            await manager.bootstrap()
            let articleURL = try await server.start()
            seedSampleData(basePort: server.port)

            try await Task.sleep(for: .milliseconds(900))
            if let win = hostWindow { configureWindow(win, size: targetSize) }
            try await Task.sleep(for: .milliseconds(700))

            // 1. Magazine Stream (iPhone)
            let feedsImg = captureWindow()
            savePNG(feedsImg, to: outURL.appendingPathComponent("01-feeds.png"))

            // 2. Extension Browser (iPhone)
            let sampleArticle = (try? modelContext.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.sortDate, order: .reverse)])))?.first
            screen = .browser(BrowserTarget(url: articleURL, title: "iOS 18.4 WKWebExtension Guide", article: sampleArticle))
            await waitAndInjectExtensionDemo()
            let browserImg = await captureWindowWithWebView(manager.activeSession?.activeTab?.webView)
            savePNG(browserImg, to: outURL.appendingPathComponent("02-extension-browser.png"))

            // 3. Extension Studio (iPhone)
            screen = .extensions
            try await Task.sleep(for: .milliseconds(650))
            let extImg = captureWindow()
            savePNG(extImg, to: outURL.appendingPathComponent("03-extension-manager.png"))

            // 4. Library Bento Grid (iPhone)
            screen = .library
            try await Task.sleep(for: .milliseconds(650))
            let libImg = captureWindow()
            savePNG(libImg, to: outURL.appendingPathComponent("04-library-bento.png"))

            // 5. Composite 4-up mobile showcase
            if let f = feedsImg, let b = browserImg, let e = extImg, let l = libImg {
                savePNG(makeShowcase(images: [l, f, b, e]), to: outURL.appendingPathComponent("showcase.png"))
            }

            // 6. Inoreader 3-column Workspace (Mac / iPad)
            if let first = sampleArticle {
                first.link = articleURL.absoluteString
                try? modelContext.save()
            }
            targetSize = NSSize(width: 1240, height: 780)
            if let win = hostWindow { configureWindow(win, size: targetSize) }
            screen = .workspace(sampleArticle)
            await waitAndInjectExtensionDemo()
            let wsImg = await captureWindowWithWebView(manager.activeSession?.activeTab?.webView)
            savePNG(wsImg, to: outURL.appendingPathComponent("05-inoreader-workspace.png"))

            server.stop()
        } catch {
            fputs("Screenshot capture failed: \(error)\n", stderr)
            server.stop()
        }
        try? await Task.sleep(for: .milliseconds(200))
        NSApplication.shared.terminate(nil)
    }

    private func waitAndInjectExtensionDemo() async {
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if let tab = manager.activeSession?.activeTab, !tab.isLoading, tab.url != nil {
                break
            }
        }
        try? await Task.sleep(for: .milliseconds(800))
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
            try? await Task.sleep(for: .milliseconds(450))
        }
    }

    private func seedSampleData(basePort: UInt16) {
        let now = Date()
        let zenn = Feed(feedURL: "https://zenn.dev/feed", title: "Zenn (日本語)", folderName: "Foreign Language")
        let willison = Feed(feedURL: "https://simonwillison.net/atom/everything/", title: "Simon Willison's Weblog", folderName: "Engineering")
        let hn = Feed(feedURL: "https://hnrss.org/frontpage", title: "Hacker News", folderName: "Engineering")
        let lemonde = Feed(feedURL: "https://www.lemonde.fr/rss/une.xml", title: "Le Monde (Français)", folderName: "Foreign Language")
        [zenn, willison, hn, lemonde].forEach { modelContext.insert($0) }

        let samples: [(Feed, String, String, String, String?, TimeInterval)] = [
            (zenn, "iOS 18.4 の WKWebExtension で Chrome 拡張機能を RSS リーダーに組み込む",
             "WKWebExtensionController を使ってアプリ内ブラウザで翻訳拡張機能をそのまま動かす設計解説。",
             "https://zenn.dev/articles/wkwebextension-rss", "http://127.0.0.1:\(basePort)/thumb-1.png", -900),
            (willison, "Running Real WebExtensions Inside WKWebView on iOS 18.4",
             "Apple's WKWebExtension APIs allow native apps to load unpacked Manifest V3 extensions with persistent chrome.storage.",
             "https://simonwillison.net/2025/wkwebextension", "http://127.0.0.1:\(basePort)/thumb-2.png", -3600),
            (lemonde, "L'intelligence artificielle transforme la lecture d'actualités multilingues",
             "Comment les extensions de traduction bilingue facilitent la veille internationale au quotidien.",
             "https://www.lemonde.fr/pixels/article", nil, -7200),
            (hn, "Show HN: ChromaRSS — iOS RSS Reader with In-App Chrome Extensions",
             "Open articles directly in an extension-ready WKWebView so Immersive Translate works natively.",
             "https://news.ycombinator.com/item?id=1", nil, -14400),
            (zenn, "Swift 6 Strict Concurrency と SwiftData 実践パターン",
             "Observable マクロと MainActor 分離を使ったモダンな iOS アプリ設計。",
             "https://zenn.dev/articles/swift6-swiftdata", nil, -21600)
        ]

        for (i, item) in samples.enumerated() {
            let a = Article(
                feedURL: item.0.feedURL,
                guid: "sample-\(i)",
                title: item.1,
                link: item.3,
                author: item.0.title,
                summary: item.2,
                imageURL: item.4,
                publishedAt: now.addingTimeInterval(item.5)
            )
            a.isStarred = (i == 0 || i == 2)
            a.isRead = (i == 4)
            a.feed = item.0
            modelContext.insert(a)
        }
        try? modelContext.save()
    }

    private func captureWindow() -> NSImage? {
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
        let base = captureWindow()
        guard let base, let webView else { return base }

        let snapConfig = WKSnapshotConfiguration()
        guard let webSnap = try? await webView.takeSnapshot(configuration: snapConfig) else { return base }

        let rectInContent = webView.convert(webView.bounds, to: contentView)
        let drawRect = NSRect(
            x: rectInContent.minX,
            y: contentView.isFlipped ? (contentView.bounds.height - rectInContent.maxY) : rectInContent.minY,
            width: rectInContent.width,
            height: rectInContent.height
        )

        let scale = win.backingScaleFactor
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(contentView.bounds.width * scale), pixelsHigh: Int(contentView.bounds.height * scale),
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
        let gap: CGFloat = 22
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

        NSColor(calibratedRed: 0.937, green: 0.945, blue: 0.968, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: totalW, height: totalH)).fill()

        for (idx, img) in images.enumerated() {
            let x = pad + CGFloat(idx) * (cardW + gap)
            let rect = NSRect(x: x, y: pad, width: cardW, height: cardH)
            let path = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
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
