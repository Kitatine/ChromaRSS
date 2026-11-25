import Foundation

public enum FeedParserError: Error, LocalizedError, Equatable {
    case emptyData
    case unsupportedFormat
    case xmlParseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyData: return "The feed response was empty."
        case .unsupportedFormat: return "This doesn't look like an RSS, Atom or JSON feed."
        case .xmlParseFailed(let m): return "Couldn't parse the feed: \(m)"
        }
    }
}

public enum FeedParser {
    public static func parse(data: Data, baseURL: URL? = nil) throws -> ParsedFeed {
        guard !data.isEmpty else { throw FeedParserError.emptyData }

        let skip: Set<UInt8> = [0x20, 0x0A, 0x0D, 0x09, 0xEF, 0xBB, 0xBF]
        if let first = data.first(where: { !skip.contains($0) }), first == UInt8(ascii: "{") {
            return try parseJSONFeed(data, baseURL: baseURL)
        }

        let delegate = FeedXMLDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let ok = parser.parse()

        guard let format = delegate.format else {
            if !ok { throw FeedParserError.xmlParseFailed(parser.parserError?.localizedDescription ?? "unknown error") }
            throw FeedParserError.unsupportedFormat
        }
        if !ok && delegate.articles.isEmpty {
            throw FeedParserError.xmlParseFailed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        let title = delegate.feedTitle.isEmpty ? (delegate.siteURL ?? "Untitled Feed") : delegate.feedTitle
        return ParsedFeed(title: title, siteURL: delegate.siteURL, description: delegate.feedDescription,
                          iconURL: delegate.iconURL, format: format, articles: delegate.articles)
    }

    // MARK: JSON Feed

    static func parseJSONFeed(_ data: Data, baseURL: URL?) throws -> ParsedFeed {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeedParserError.unsupportedFormat
        }
        guard let version = obj["version"] as? String, version.hasPrefix("https://jsonfeed.org/version/") else {
            throw FeedParserError.unsupportedFormat
        }
        let items = obj["items"] as? [[String: Any]] ?? []
        var articles: [ParsedArticle] = []
        for item in items {
            let link = resolve((item["url"] as? String) ?? (item["external_url"] as? String) ?? "", base: baseURL)
            let title = (item["title"] as? String) ?? ""
            let content = item["content_html"] as? String
            let text = item["content_text"] as? String
            let summary = (item["summary"] as? String) ?? text
            var author: String?
            if let authors = item["authors"] as? [[String: Any]], let n = authors.first?["name"] as? String { author = n }
            else if let a = item["author"] as? [String: Any], let n = a["name"] as? String { author = n }
            let date = DateParser.parse(item["date_published"] as? String) ?? DateParser.parse(item["date_modified"] as? String)
            let guid = (item["id"] as? String) ?? (item["id"] as? Int).map(String.init) ?? fallbackGUID(link: link, title: title, date: date)
            articles.append(ParsedArticle(
                guid: guid, title: title.isEmpty ? link : title, link: link, author: author, summary: summary,
                contentHTML: content, imageURL: (item["image"] as? String).map { resolve($0, base: baseURL) } ?? firstImage(in: content),
                publishedAt: date))
        }
        let site = (obj["home_page_url"] as? String).map { resolve($0, base: baseURL) }
        let icon = ((obj["icon"] as? String) ?? (obj["favicon"] as? String)).map { resolve($0, base: baseURL) }
        return ParsedFeed(title: (obj["title"] as? String) ?? site ?? "Untitled Feed", siteURL: site,
                          description: obj["description"] as? String, iconURL: icon, format: .jsonFeed, articles: articles)
    }

    // MARK: Helpers

    static func resolve(_ s: String, base: URL?) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if let base, let u = URL(string: t, relativeTo: base) { return u.absoluteString }
        return t
    }

    static func fallbackGUID(link: String, title: String, date: Date?) -> String {
        if !link.isEmpty { return link }
        var hash: UInt64 = 0xcbf29ce484222325
        for b in (title + String(date?.timeIntervalSince1970 ?? 0)).utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return "generated-" + String(hash, radix: 16)
    }

    static func firstImage(in html: String?) -> String? {
        guard let html, let regex = try? NSRegularExpression(pattern: "<img[^>]+src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

// MARK: - XML

final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    struct Builder {
        var guid: String?
        var title = ""
        var link: String?
        var author: String?
        var summary: String?
        var content: String?
        var image: String?
        var published: String?
        var updated: String?
    }

    let baseURL: URL?
    var format: FeedFormat?
    var isAtom = false
    var feedTitle = ""
    var siteURL: String?
    var feedDescription: String?
    var iconURL: String?
    var articles: [ParsedArticle] = []

    private var path: [String] = []
    private var text = ""
    private var inItem = false
    private var cur = Builder()

    init(baseURL: URL?) { self.baseURL = baseURL }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let n = elementName.lowercased()
        path.append(n)
        text = ""
        switch n {
        case "rss", "rdf:rdf": format = .rss
        case "feed": format = .atom; isAtom = true
        case "item", "entry":
            inItem = true
            cur = Builder()
        case "link":
            guard let href = attributeDict["href"] else { break }
            let rel = (attributeDict["rel"] ?? "alternate").lowercased()
            if inItem {
                if rel == "alternate" || (cur.link == nil && rel != "self" && rel != "enclosure") {
                    if rel == "alternate" || cur.link == nil { cur.link = FeedParser.resolve(href, base: baseURL) }
                }
                if rel == "enclosure", (attributeDict["type"] ?? "").hasPrefix("image"), cur.image == nil {
                    cur.image = FeedParser.resolve(href, base: baseURL)
                }
            } else if rel == "alternate" {
                siteURL = FeedParser.resolve(href, base: baseURL)
            }
        case "enclosure":
            if inItem, let url = attributeDict["url"] {
                let type = (attributeDict["type"] ?? "").lowercased()
                let lower = url.lowercased()
                if type.hasPrefix("image") || [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains(where: { lower.contains($0) }) {
                    cur.image = FeedParser.resolve(url, base: baseURL)
                }
            }
        case "media:content", "media:thumbnail":
            if inItem, cur.image == nil, let url = attributeDict["url"] {
                let type = (attributeDict["type"] ?? attributeDict["medium"] ?? "image").lowercased()
                if n == "media:thumbnail" || type.hasPrefix("image") {
                    cur.image = FeedParser.resolve(url, base: baseURL)
                }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let n = elementName.lowercased()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = path.count >= 2 ? path[path.count - 2] : ""
        defer { path.removeLast(); text = "" }

        if inItem {
            let direct = parent == "item" || parent == "entry"
            switch n {
            case "title" where direct: cur.title = HTMLTextExtractor.decodeEntities(t)
            case "guid" where direct, "id" where direct: if !t.isEmpty { cur.guid = t }
            case "link" where direct && !isAtom && !t.isEmpty: cur.link = FeedParser.resolve(t, base: baseURL)
            case "description" where direct, "summary" where direct: if !t.isEmpty { cur.summary = t }
            case "content:encoded" where direct, "content" where direct: if !t.isEmpty { cur.content = t }
            case "dc:creator" where direct, "author" where direct && !isAtom: if !t.isEmpty { cur.author = t }
            case "name" where parent == "author": if !t.isEmpty { cur.author = t }
            case "pubdate" where direct, "dc:date" where direct, "published" where direct: if !t.isEmpty { cur.published = t }
            case "updated" where direct: if !t.isEmpty { cur.updated = t }
            case "item", "entry":
                finalizeItem()
                inItem = false
            default: break
            }
            return
        }

        switch n {
        case "title" where parent == "channel" || parent == "feed": feedTitle = HTMLTextExtractor.decodeEntities(t)
        case "description" where parent == "channel", "subtitle" where parent == "feed": if !t.isEmpty { feedDescription = t }
        case "link" where parent == "channel" && !isAtom: if !t.isEmpty { siteURL = FeedParser.resolve(t, base: baseURL) }
        case "icon" where parent == "feed", "logo" where parent == "feed": if !t.isEmpty, iconURL == nil || n == "icon" { iconURL = FeedParser.resolve(t, base: baseURL) }
        case "url" where parent == "image": if !t.isEmpty { iconURL = FeedParser.resolve(t, base: baseURL) }
        default: break
        }
    }

    private func finalizeItem() {
        let date = DateParser.parse(cur.published) ?? DateParser.parse(cur.updated)
        let link = cur.link ?? ""
        let guid = cur.guid ?? FeedParser.fallbackGUID(link: link, title: cur.title, date: date)
        let image = cur.image ?? FeedParser.firstImage(in: cur.content) ?? FeedParser.firstImage(in: cur.summary)
        articles.append(ParsedArticle(
            guid: guid, title: cur.title.isEmpty ? (link.isEmpty ? "Untitled" : link) : cur.title, link: link,
            author: cur.author, summary: cur.summary, contentHTML: cur.content, imageURL: image, publishedAt: date))
    }
}
