import Foundation

public enum OPMLError: Error, LocalizedError {
    case parseFailed(String)
    public var errorDescription: String? {
        switch self {
        case .parseFailed(let m): return "Couldn't read the OPML file: \(m)"
        }
    }
}

public enum OPMLCodec {
    public static func parse(data: Data) throws -> [OPMLOutlineItem] {
        let delegate = OPMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        let ok = parser.parse()
        if !ok && delegate.items.isEmpty {
            throw OPMLError.parseFailed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return delegate.items
    }

    public static func export(items: [OPMLOutlineItem], title: String = "ChromaRSS Subscriptions") -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">\n  <head>\n    <title>\(escape(title))</title>\n  </head>\n  <body>\n"
        func line(_ item: OPMLOutlineItem, indent: String) -> String {
            var s = "\(indent)<outline type=\"rss\" text=\"\(escape(item.title))\" title=\"\(escape(item.title))\" xmlUrl=\"\(escape(item.feedURL))\""
            if let site = item.siteURL, !site.isEmpty { s += " htmlUrl=\"\(escape(site))\"" }
            return s + "/>\n"
        }
        for item in items where (item.folder ?? "").isEmpty { out += line(item, indent: "    ") }
        let folders = Array(Set(items.compactMap { $0.folder }.filter { !$0.isEmpty })).sorted()
        for folder in folders {
            out += "    <outline text=\"\(escape(folder))\" title=\"\(escape(folder))\">\n"
            for item in items where item.folder == folder { out += line(item, indent: "      ") }
            out += "    </outline>\n"
        }
        out += "  </body>\n</opml>\n"
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

final class OPMLDelegate: NSObject, XMLParserDelegate {
    var items: [OPMLOutlineItem] = []
    private var stack: [String?] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName.lowercased() == "outline" else { return }
        var attrs: [String: String] = [:]
        for (k, v) in attributeDict { attrs[k.lowercased()] = v }
        if let xml = attrs["xmlurl"], !xml.isEmpty {
            let title = attrs["title"] ?? attrs["text"] ?? xml
            let folder = stack.compactMap { $0 }.last
            items.append(OPMLOutlineItem(title: title, feedURL: xml, siteURL: attrs["htmlurl"], folder: folder))
            stack.append(nil)
        } else {
            stack.append(attrs["title"] ?? attrs["text"])
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "outline", !stack.isEmpty { stack.removeLast() }
    }
}
