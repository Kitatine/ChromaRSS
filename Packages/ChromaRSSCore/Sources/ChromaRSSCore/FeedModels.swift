import Foundation

public enum FeedFormat: String, Sendable, Equatable {
    case rss, atom, jsonFeed
}

public struct ParsedArticle: Sendable, Equatable {
    public var guid: String
    public var title: String
    public var link: String
    public var author: String?
    public var summary: String?
    public var contentHTML: String?
    public var imageURL: String?
    public var publishedAt: Date?

    public init(guid: String, title: String, link: String, author: String? = nil, summary: String? = nil,
                contentHTML: String? = nil, imageURL: String? = nil, publishedAt: Date? = nil) {
        self.guid = guid
        self.title = title
        self.link = link
        self.author = author
        self.summary = summary
        self.contentHTML = contentHTML
        self.imageURL = imageURL
        self.publishedAt = publishedAt
    }
}

public struct ParsedFeed: Sendable, Equatable {
    public var title: String
    public var siteURL: String?
    public var description: String?
    public var iconURL: String?
    public var format: FeedFormat
    public var articles: [ParsedArticle]

    public init(title: String, siteURL: String? = nil, description: String? = nil, iconURL: String? = nil,
                format: FeedFormat, articles: [ParsedArticle]) {
        self.title = title
        self.siteURL = siteURL
        self.description = description
        self.iconURL = iconURL
        self.format = format
        self.articles = articles
    }
}

public struct OPMLOutlineItem: Sendable, Equatable {
    public var title: String
    public var feedURL: String
    public var siteURL: String?
    public var folder: String?

    public init(title: String, feedURL: String, siteURL: String? = nil, folder: String? = nil) {
        self.title = title
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.folder = folder
    }
}

public enum HTMLTextExtractor {
    /// Strips tags/scripts/styles, decodes entities and collapses whitespace.
    public static func plainText(from html: String, maxLength: Int = 280, preserveParagraphs: Bool = false) -> String {
        var s = html
        s = replace(s, pattern: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ")
        if preserveParagraphs {
            s = replace(s, pattern: "(?i)(</p>|<br\\s*/?>|</div>|</h[1-6]>|</li>|</blockquote>)", with: "\n\n")
        }
        s = replace(s, pattern: "<[^>]+>", with: " ")
        s = decodeEntities(s)
        if preserveParagraphs {
            s = replace(s, pattern: "[ \\t\\u{00A0}]+", with: " ")
            s = replace(s, pattern: " ?\\n ?", with: "\n")
            s = replace(s, pattern: "\\n{3,}", with: "\n\n")
        } else {
            s = replace(s, pattern: "\\s+", with: " ")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if maxLength > 0, s.count > maxLength {
            s = String(s.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return s
    }

    public static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        let ns = input as NSString
        var result = ""
        var last = 0
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);", options: [.caseInsensitive]) {
            for m in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let isHex = ns.substring(with: m.range(at: 1)).lowercased() == "x"
                let num = ns.substring(with: m.range(at: 2))
                if let v = UInt32(num, radix: isHex ? 16 : 10), let u = Unicode.Scalar(v) {
                    result += String(Character(u))
                } else {
                    result += ns.substring(with: m.range)
                }
                last = m.range.location + m.range.length
            }
        }
        result += ns.substring(from: last)
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
            ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–"), ("&amp;", "&")
        ]
        for (k, v) in named { result = result.replacingOccurrences(of: k, with: v) }
        return result
    }

    static func replace(_ s: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}
