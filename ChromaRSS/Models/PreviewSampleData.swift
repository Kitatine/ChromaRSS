import SwiftUI
import SwiftData

@MainActor
enum PreviewSampleData {
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Feed.self, Article.self, configurations: config)
        } catch {
            fatalError("Preview ModelContainer failed: \(error)")
        }

        let context = container.mainContext
        let zenn = Feed(feedURL: "https://zenn.dev/feed", title: "Zenn (日本語)", folderName: "Foreign Language")
        let willison = Feed(feedURL: "https://simonwillison.net/atom/everything/", title: "Simon Willison's Weblog", folderName: "Tech")
        let hn = Feed(feedURL: "https://hnrss.org/frontpage", title: "Hacker News", folderName: "Tech")
        [zenn, willison, hn].forEach { context.insert($0) }

        let now = Date()
        let items: [(Feed, String, String, String, TimeInterval, Bool, Bool)] = [
            (zenn, "iOS 18.4 の WKWebExtension で Chrome 拡張機能を動かす",
             "WKWebExtensionController を使ってアプリ内ブラウザで翻訳拡張機能をそのまま実行する設計解説。",
             "https://zenn.dev/articles/wkwebextension", -900, false, true),
            (willison, "Running WebExtensions Inside WKWebView",
             "Using WKWebExtensionController for persistent extension storage and content scripts.",
             "https://simonwillison.net/2025/wkwebextension", -3600, false, false),
            (hn, "ChromaRSS: iOS RSS Reader with In-App Chrome Extensions",
             "Open feed articles straight into an extension-enabled WKWebView.",
             "https://news.ycombinator.com/item?id=1", -7200, true, false)
        ]

        for (i, item) in items.enumerated() {
            let article = Article(
                feedURL: item.0.feedURL,
                guid: "preview-\(i)",
                title: item.1,
                link: item.3,
                author: item.0.title,
                summary: item.2,
                publishedAt: now.addingTimeInterval(item.4)
            )
            article.isRead = item.5
            article.isStarred = item.6
            article.feed = item.0
            context.insert(article)
        }
        return container
    }

    static func sampleArticle(in container: ModelContainer) -> Article {
        if let first = try? container.mainContext.fetch(FetchDescriptor<Article>()).first {
            return first
        }
        return Article(
            feedURL: "https://zenn.dev/feed",
            guid: "fallback",
            title: "Sample Article",
            link: "https://example.com",
            summary: "Sample article summary."
        )
    }
}

private struct PreviewEnvironmentModifier: ViewModifier {
    @State private var container: ModelContainer
    @State private var settings: AppSettings
    @State private var manager: ExtensionManager
    @State private var sync = FeedSyncService()

    @MainActor
    init(initialContainer: ModelContainer? = nil) {
        let s = AppSettings()
        _container = State(initialValue: initialContainer ?? PreviewSampleData.makeContainer())
        _settings = State(initialValue: s)
        _manager = State(initialValue: ExtensionManager(settings: s))
    }

    func body(content: Content) -> some View {
        content
            .environment(settings)
            .environment(manager)
            .environment(sync)
            .modelContainer(container)
    }
}

extension View {
    @MainActor
    func chromaPreviewEnvironment(container: ModelContainer? = nil) -> some View {
        modifier(PreviewEnvironmentModifier(initialContainer: container))
    }
}
