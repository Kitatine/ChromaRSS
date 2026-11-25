import Foundation

public struct DiscoveredFeed: Sendable, Equatable {
    public let title: String?
    public let url: URL
    public init(title: String?, url: URL) {
        self.title = title
        self.url = url
    }
}

public enum FeedDiscoveryError: Error, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case noFeedFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid URL."
        case .httpStatus(let c): return "The server responded with HTTP \(c)."
        case .noFeedFound: return "No RSS, Atom or JSON feed could be found at that address."
        }
    }
}

public enum FeedDiscovery {
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"

    public static func normalizedURL(from input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("feed://") { s = "https://" + s.dropFirst("feed://".count) }
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s), let host = u.host, !host.isEmpty else { return nil }
        return u
    }

    public static func extractFeedLinks(fromHTML html: String, baseURL: URL) -> [DiscoveredFeed] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]),
              let attrRegex = try? NSRegularExpression(pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')") else { return [] }
        let types: Set<String> = ["application/rss+xml", "application/atom+xml", "application/feed+json", "application/json", "text/xml", "application/xml"]
        let ns = html as NSString
        var found: [DiscoveredFeed] = []
        for m in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            let tns = tag as NSString
            var attrs: [String: String] = [:]
            for a in attrRegex.matches(in: tag, range: NSRange(location: 0, length: tns.length)) {
                let key = tns.substring(with: a.range(at: 1)).lowercased()
                let r2 = a.range(at: 2), r3 = a.range(at: 3)
                attrs[key] = r2.location != NSNotFound ? tns.substring(with: r2) : tns.substring(with: r3)
            }
            guard let rel = attrs["rel"]?.lowercased(), rel.contains("alternate"),
                  let type = attrs["type"]?.lowercased(), types.contains(type),
                  let href = attrs["href"], !href.isEmpty,
                  let url = URL(string: HTMLTextExtractor.decodeEntities(href), relativeTo: baseURL)?.absoluteURL else { continue }
            if !found.contains(where: { $0.url == url }) {
                found.append(DiscoveredFeed(title: attrs["title"].map(HTMLTextExtractor.decodeEntities), url: url))
            }
        }
        return found
    }

    public static func fetch(url: URL, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/rss+xml, application/atom+xml, application/feed+json, application/xml, text/xml, text/html;q=0.8, */*;q=0.5", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedDiscoveryError.httpStatus(http.statusCode)
        }
        return (data, response)
    }

    public static func fetchFeed(at url: URL, session: URLSession = .shared) async throws -> ParsedFeed {
        let (data, response) = try await fetch(url: url, session: session)
        return try FeedParser.parse(data: data, baseURL: response.url ?? url)
    }

    public static func resolveFeed(from userInput: String, session: URLSession = .shared) async throws -> (feedURL: URL, parsedFeed: ParsedFeed) {
        guard let url = normalizedURL(from: userInput) else { throw FeedDiscoveryError.invalidURL }
        let (data, response) = try await fetch(url: url, session: session)
        let finalURL = response.url ?? url
        if let feed = try? FeedParser.parse(data: data, baseURL: finalURL) {
            return (finalURL, feed)
        }

        var candidates: [URL] = []
        if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            candidates += extractFeedLinks(fromHTML: html, baseURL: finalURL).map(\.url)
        }
        if var comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: true) {
            comps.path = ""; comps.query = nil; comps.fragment = nil
            if let origin = comps.url {
                for p in ["/feed", "/rss.xml", "/atom.xml", "/index.xml", "/feed.xml", "/feed.json"] {
                    if let u = URL(string: p, relativeTo: origin)?.absoluteURL, !candidates.contains(u) { candidates.append(u) }
                }
            }
        }
        for c in candidates {
            if let (d, r) = try? await fetch(url: c, session: session),
               let feed = try? FeedParser.parse(data: d, baseURL: r.url ?? c) {
                return (r.url ?? c, feed)
            }
        }
        throw FeedDiscoveryError.noFeedFound
    }
}
