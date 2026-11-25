import Foundation
import SwiftData
import Observation
import ChromaRSSCore

struct StarterFeedPreset: Identifiable, Sendable {
    let title: String
    let url: String
    let folder: String
    var id: String { url }

    static let all: [StarterFeedPreset] = [
        .init(title: "Hacker News", url: "https://hnrss.org/frontpage", folder: "Tech"),
        .init(title: "Simon Willison's Weblog", url: "https://simonwillison.net/atom/everything/", folder: "Tech"),
        .init(title: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", folder: "Tech"),
        .init(title: "Daring Fireball", url: "https://daringfireball.net/feeds/main", folder: "Tech"),
        .init(title: "Zenn (日本語)", url: "https://zenn.dev/feed", folder: "Foreign Language"),
        .init(title: "DW News", url: "https://rss.dw.com/rdf/rss-en-all", folder: "Foreign Language"),
        .init(title: "Le Monde (Français)", url: "https://www.lemonde.fr/rss/une.xml", folder: "Foreign Language")
    ]
}

@MainActor
@Observable
final class FeedSyncService {
    var isRefreshing = false
    var lastError: String?

    // MARK: Subscribe

    @discardableResult
    func subscribe(urlInput: String, folderName: String?, preferExtensionBrowser: Bool, in context: ModelContext) async throws -> Feed {
        let (url, parsed) = try await FeedDiscovery.resolveFeed(from: urlInput)
        let key = url.absoluteString
        let feed: Feed
        if let existing = try fetchFeed(url: key, in: context) {
            feed = existing
            if let newFolder = folderName?.nilIfEmpty {
                existing.folderName = newFolder
            }
        } else {
            feed = Feed(feedURL: key, title: parsed.title, siteURL: parsed.siteURL, feedDescription: parsed.description,
                        iconURL: parsed.iconURL, folderName: folderName?.nilIfEmpty, preferExtensionBrowser: preferExtensionBrowser)
            context.insert(feed)
        }
        apply(parsed, to: feed, in: context)
        try context.save()
        lastError = nil
        return feed
    }

    func addStarterFeeds(preferExtensionBrowser: Bool, in context: ModelContext) async {
        isRefreshing = true
        defer { isRefreshing = false }
        for preset in StarterFeedPreset.all {
            if (try? fetchFeed(url: preset.url, in: context)) ?? nil != nil { continue }
            // Insert immediately so the list isn't empty, then fill from the network.
            let feed = Feed(feedURL: preset.url, title: preset.title, folderName: preset.folder, preferExtensionBrowser: preferExtensionBrowser)
            context.insert(feed)
        }
        try? context.save()
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        await refreshAll(feeds: feeds, in: context)
    }

    // MARK: Refresh

    nonisolated static func fetch(_ urlString: String) async throws -> ParsedFeed {
        guard let url = URL(string: urlString) else { throw FeedDiscoveryError.invalidURL }
        return try await FeedDiscovery.fetchFeed(at: url)
    }

    func refresh(feed: Feed, in context: ModelContext) async throws {
        let parsed = try await Self.fetch(feed.feedURL)
        apply(parsed, to: feed, in: context)
        try context.save()
    }

    func refreshAll(feeds: [Feed], in context: ModelContext) async {
        guard !feeds.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let urls = feeds.map(\.feedURL)
        let results = await withTaskGroup(of: (String, ParsedFeed?).self) { group -> [(String, ParsedFeed?)] in
            for u in urls {
                group.addTask { (u, try? await Self.fetch(u)) }
            }
            var out: [(String, ParsedFeed?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var failures = 0
        for (url, parsed) in results {
            guard let parsed else { failures += 1; continue }
            if let feed = feeds.first(where: { $0.feedURL == url }) { apply(parsed, to: feed, in: context) }
        }
        try? context.save()
        lastError = failures > 0 ? "\(failures) feed(s) failed to refresh." : nil
    }

    private func apply(_ parsed: ParsedFeed, to feed: Feed, in context: ModelContext) {
        if feed.title.isEmpty || feed.articles.isEmpty { feed.title = parsed.title.isEmpty ? feed.title : parsed.title }
        feed.siteURL = parsed.siteURL ?? feed.siteURL
        feed.feedDescription = parsed.description ?? feed.feedDescription
        feed.iconURL = parsed.iconURL ?? feed.iconURL
        feed.lastUpdated = Date()
        let existing = Set(feed.articles.map(\.uniqueKey))
        for a in parsed.articles {
            let key = "\(feed.feedURL)|\(a.guid)"
            if existing.contains(key) { continue }
            let article = Article(feedURL: feed.feedURL, guid: a.guid, title: a.title, link: a.link, author: a.author,
                                  summary: a.summary, contentHTML: a.contentHTML, imageURL: a.imageURL, publishedAt: a.publishedAt)
            article.feed = feed
            context.insert(article)
        }
    }

    private func fetchFeed(url: String, in context: ModelContext) throws -> Feed? {
        var d = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == url })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    // MARK: OPML

    func importOPML(data: Data, preferExtensionBrowser: Bool, in context: ModelContext) async throws -> Int {
        let items = try OPMLCodec.parse(data: data)
        var added = 0
        for item in items {
            if try fetchFeed(url: item.feedURL, in: context) != nil { continue }
            context.insert(Feed(feedURL: item.feedURL, title: item.title, siteURL: item.siteURL,
                                folderName: item.folder, preferExtensionBrowser: preferExtensionBrowser))
            added += 1
        }
        try context.save()
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        await refreshAll(feeds: feeds, in: context)
        return added
    }

    func exportOPML(feeds: [Feed]) -> String {
        OPMLCodec.export(items: feeds.map {
            OPMLOutlineItem(title: $0.title, feedURL: $0.feedURL, siteURL: $0.siteURL, folder: $0.folderName)
        })
    }
}

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
