import Foundation
import SwiftData

@Model
final class Feed {
    @Attribute(.unique) var feedURL: String
    var title: String
    var siteURL: String?
    var feedDescription: String?
    var iconURL: String?
    var folderName: String?
    var preferExtensionBrowser: Bool
    var lastUpdated: Date?
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Article.feed) var articles: [Article] = []

    init(feedURL: String, title: String, siteURL: String? = nil, feedDescription: String? = nil, iconURL: String? = nil,
         folderName: String? = nil, preferExtensionBrowser: Bool = true) {
        self.feedURL = feedURL
        self.title = title
        self.siteURL = siteURL
        self.feedDescription = feedDescription
        self.iconURL = iconURL
        self.folderName = folderName
        self.preferExtensionBrowser = preferExtensionBrowser
        self.createdAt = Date()
    }

    var unreadCount: Int { articles.filter { !$0.isRead }.count }
}

@Model
final class Article {
    #Index<Article>([\.feedURL, \.sortDate], [\.sortDate], [\.isRead], [\.isStarred])

    @Attribute(.unique) var uniqueKey: String
    var feedURL: String
    var guid: String
    var title: String
    var link: String
    var author: String?
    var summary: String?
    var contentHTML: String?
    var imageURL: String?
    var publishedAt: Date?
    var sortDate: Date
    var isRead: Bool
    var isStarred: Bool
    var feed: Feed?

    init(feedURL: String, guid: String, title: String, link: String, author: String? = nil, summary: String? = nil,
         contentHTML: String? = nil, imageURL: String? = nil, publishedAt: Date? = nil) {
        self.uniqueKey = "\(feedURL)|\(guid)"
        self.feedURL = feedURL
        self.guid = guid
        self.title = title
        self.link = link
        self.author = author
        self.summary = summary
        self.contentHTML = contentHTML
        self.imageURL = imageURL
        self.publishedAt = publishedAt
        self.sortDate = publishedAt ?? Date()
        self.isRead = false
        self.isStarred = false
    }

    var resolvedURL: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = URL(string: trimmed) { return direct }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }
}
