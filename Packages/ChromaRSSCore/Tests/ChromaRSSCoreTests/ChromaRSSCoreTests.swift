import XCTest
import Compression
@testable import ChromaRSSCore

final class FeedParserTests: XCTestCase {
    func testRSS2WithContentEncoded() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel>
            <title>Example &amp; Co</title>
            <link>https://example.com/</link>
            <description>Desc</description>
            <image><url>https://example.com/icon.png</url></image>
            <item>
              <title>Hello</title>
              <link>/posts/1</link>
              <guid>g-1</guid>
              <dc:creator>Alice</dc:creator>
              <pubDate>Tue, 10 Jun 2025 04:00:00 GMT</pubDate>
              <description><![CDATA[<p>Summary</p>]]></description>
              <content:encoded><![CDATA[<p>Full <img src="https://example.com/a.jpg"></p>]]></content:encoded>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), baseURL: URL(string: "https://example.com/feed")!)
        XCTAssertEqual(feed.format, .rss)
        XCTAssertEqual(feed.title, "Example & Co")
        XCTAssertEqual(feed.siteURL, "https://example.com/")
        XCTAssertEqual(feed.iconURL, "https://example.com/icon.png")
        XCTAssertEqual(feed.articles.count, 1)
        let a = feed.articles[0]
        XCTAssertEqual(a.guid, "g-1")
        XCTAssertEqual(a.link, "https://example.com/posts/1")
        XCTAssertEqual(a.author, "Alice")
        XCTAssertEqual(a.summary, "<p>Summary</p>")
        XCTAssertTrue(a.contentHTML?.contains("Full") == true)
        XCTAssertEqual(a.imageURL, "https://example.com/a.jpg")
        XCTAssertNotNil(a.publishedAt)
    }

    func testAtom() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Blog</title>
          <subtitle>Sub</subtitle>
          <link rel="self" href="https://a.example/atom"/>
          <link rel="alternate" href="https://a.example/"/>
          <entry>
            <id>tag:a.example,2025:1</id>
            <title>Entry One</title>
            <link rel="alternate" href="https://a.example/1"/>
            <author><name>Bob</name></author>
            <published>2025-06-10T12:00:00Z</published>
            <updated>2025-06-11T12:00:00Z</updated>
            <summary>Short</summary>
            <content type="html">&lt;p&gt;Body&lt;/p&gt;</content>
          </entry>
        </feed>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(feed.format, .atom)
        XCTAssertEqual(feed.title, "Atom Blog")
        XCTAssertEqual(feed.siteURL, "https://a.example/")
        XCTAssertEqual(feed.description, "Sub")
        XCTAssertEqual(feed.articles.count, 1)
        let a = feed.articles[0]
        XCTAssertEqual(a.guid, "tag:a.example,2025:1")
        XCTAssertEqual(a.link, "https://a.example/1")
        XCTAssertEqual(a.author, "Bob")
        XCTAssertEqual(a.contentHTML, "<p>Body</p>")
        XCTAssertEqual(a.publishedAt, ISO8601DateFormatter().date(from: "2025-06-10T12:00:00Z"))
    }

    func testJSONFeed() throws {
        let json = """
        {"version":"https://jsonfeed.org/version/1.1","title":"JF","home_page_url":"https://j.example/",
         "items":[{"id":"1","url":"https://j.example/1","title":"One","content_html":"<p>x</p>",
         "date_published":"2025-06-10T12:00:00Z","authors":[{"name":"Carol"}],"image":"https://j.example/i.png"}]}
        """
        let feed = try FeedParser.parse(data: Data(json.utf8))
        XCTAssertEqual(feed.format, .jsonFeed)
        XCTAssertEqual(feed.title, "JF")
        XCTAssertEqual(feed.articles.first?.author, "Carol")
        XCTAssertEqual(feed.articles.first?.imageURL, "https://j.example/i.png")
    }

    func testRSS1RDF() throws {
        let xml = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel><title>RDF Feed</title><link>https://r.example/</link></channel>
          <item><title>R1</title><link>https://r.example/1</link><dc:date>2025-06-10T12:00:00Z</dc:date></item>
        </rdf:RDF>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(feed.title, "RDF Feed")
        XCTAssertEqual(feed.articles.count, 1)
        XCTAssertEqual(feed.articles[0].guid, "https://r.example/1")
    }

    func testHTMLIsRejected() {
        XCTAssertThrowsError(try FeedParser.parse(data: Data("<html><body>hi</body></html>".utf8)))
        XCTAssertThrowsError(try FeedParser.parse(data: Data()))
    }

    func testPlainText() {
        XCTAssertEqual(HTMLTextExtractor.plainText(from: "<p>Tom &amp; Jerry&#39;s <b>show</b></p><script>x()</script>"), "Tom & Jerry's show")
        XCTAssertEqual(HTMLTextExtractor.plainText(from: "<p>a</p><p>b</p>", maxLength: 0, preserveParagraphs: true), "a\n\nb")
    }

    func testDateFormats() {
        XCTAssertNotNil(DateParser.parse("Tue, 10 Jun 2025 04:00:00 +0000"))
        XCTAssertNotNil(DateParser.parse("Tue, 10 Jun 2025 04:00:00 GMT"))
        XCTAssertNotNil(DateParser.parse("2025-06-10T04:00:00.123Z"))
        XCTAssertNotNil(DateParser.parse("2025-06-10"))
        XCTAssertNil(DateParser.parse("garbage"))
    }
}

final class DiscoveryAndOPMLTests: XCTestCase {
    func testExtractFeedLinks() {
        let html = """
        <html><head>
        <link rel="stylesheet" href="/a.css">
        <link rel="alternate" type="application/rss+xml" title="Blog &amp; News" href="/feed.xml">
        <link href='https://other.example/atom' type='application/atom+xml' rel='alternate'>
        </head></html>
        """
        let links = FeedDiscovery.extractFeedLinks(fromHTML: html, baseURL: URL(string: "https://example.com/blog/")!)
        XCTAssertEqual(links.map(\.url.absoluteString), ["https://example.com/feed.xml", "https://other.example/atom"])
        XCTAssertEqual(links.first?.title, "Blog & News")
    }

    func testNormalizeURL() {
        XCTAssertEqual(FeedDiscovery.normalizedURL(from: "example.com/rss")?.absoluteString, "https://example.com/rss")
        XCTAssertEqual(FeedDiscovery.normalizedURL(from: "feed://example.com/rss")?.absoluteString, "https://example.com/rss")
        XCTAssertNil(FeedDiscovery.normalizedURL(from: "   "))
    }

    func testOPMLRoundTrip() throws {
        let items = [
            OPMLOutlineItem(title: "Solo", feedURL: "https://s.example/feed", siteURL: "https://s.example"),
            OPMLOutlineItem(title: "A & B", feedURL: "https://a.example/feed?x=1&y=2", folder: "Tech"),
            OPMLOutlineItem(title: "C", feedURL: "https://c.example/feed", siteURL: "https://c.example", folder: "Tech"),
            OPMLOutlineItem(title: "D", feedURL: "https://d.example/feed", folder: "News")
        ]
        let xml = OPMLCodec.export(items: items)
        let parsed = try OPMLCodec.parse(data: Data(xml.utf8))
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed.first(where: { $0.title == "Solo" })?.folder, nil)
        XCTAssertEqual(parsed.first(where: { $0.title == "A & B" })?.feedURL, "https://a.example/feed?x=1&y=2")
        XCTAssertEqual(parsed.first(where: { $0.title == "A & B" })?.folder, "Tech")
        XCTAssertEqual(parsed.first(where: { $0.title == "D" })?.folder, "News")
        XCTAssertEqual(parsed.first(where: { $0.title == "C" })?.siteURL, "https://c.example")
    }
}

// MARK: - Package tests

func le16Data(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
func le32Data(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]) }

func rawDeflate(_ d: Data) -> Data {
    let cap = d.count + 1024
    var dst = [UInt8](repeating: 0, count: cap)
    let src = [UInt8](d)
    let n = src.withUnsafeBufferPointer { sp in
        compression_encode_buffer(&dst, cap, sp.baseAddress!, sp.count, nil, COMPRESSION_ZLIB)
    }
    return Data(dst[0..<n])
}

func makeZIP(_ entries: [(name: String, data: Data, deflate: Bool)]) -> Data {
    var out = Data()
    var central = Data()
    for e in entries {
        let name = Data(e.name.utf8)
        var payload = e.data
        var method = 0
        if e.deflate && !e.data.isEmpty { payload = rawDeflate(e.data); method = 8 }
        let offset = out.count
        out += le32Data(0x04034b50) + le16Data(20) + le16Data(0) + le16Data(method) + le16Data(0) + le16Data(0)
        out += le32Data(0) + le32Data(payload.count) + le32Data(e.data.count) + le16Data(name.count) + le16Data(0)
        out += name + payload
        central += le32Data(0x02014b50) + le16Data(20) + le16Data(20) + le16Data(0) + le16Data(method) + le16Data(0) + le16Data(0)
        central += le32Data(0) + le32Data(payload.count) + le32Data(e.data.count) + le16Data(name.count)
        central += le16Data(0) + le16Data(0) + le16Data(0) + le16Data(0) + le32Data(0) + le32Data(offset) + name
    }
    let cdOffset = out.count
    out += central
    out += le32Data(0x06054b50) + le16Data(0) + le16Data(0) + le16Data(entries.count) + le16Data(entries.count)
    out += le32Data(central.count) + le32Data(cdOffset) + le16Data(0)
    return out
}

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("chroma-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class PackageTests: XCTestCase {
    func testCRX3Unwrap() throws {
        let zip = makeZIP([("a.txt", Data("hi".utf8), false)])
        let header = Data("Cr24".utf8) + le32Data(3) + le32Data(5) + Data(repeating: 7, count: 5)
        let out = try CRXUnpacker.extractZIPData(fromCRXOrZIP: header + zip)
        XCTAssertEqual(out, zip)
    }

    func testCRX2Unwrap() throws {
        let zip = makeZIP([("a.txt", Data("hi".utf8), false)])
        let header = Data("Cr24".utf8) + le32Data(2) + le32Data(3) + le32Data(4) + Data(repeating: 1, count: 7)
        XCTAssertEqual(try CRXUnpacker.extractZIPData(fromCRXOrZIP: header + zip), zip)
    }

    func testPlainZIPPassthroughAndGarbage() throws {
        let zip = makeZIP([("a.txt", Data("hi".utf8), false)])
        XCTAssertEqual(try CRXUnpacker.extractZIPData(fromCRXOrZIP: zip), zip)
        XCTAssertThrowsError(try CRXUnpacker.extractZIPData(fromCRXOrZIP: Data("<html>".utf8)))
        let bad = Data("Cr24".utf8) + le32Data(3) + le32Data(500)
        XCTAssertThrowsError(try CRXUnpacker.extractZIPData(fromCRXOrZIP: bad))
    }

    func testUnzipDeflateStoredNested() throws {
        let big = Data(String(repeating: "chroma rss extension payload ", count: 200).utf8)
        let zip = makeZIP([
            ("wrapper/", Data(), false),
            ("wrapper/manifest.json", Data("{\"a\":1}".utf8), false),
            ("wrapper/js/app.js", big, true),
            ("wrapper/empty.txt", Data(), true),
            ("__MACOSX/wrapper/._x", Data("junk".utf8), false)
        ])
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ZIPExtractor.unzip(data: zip, to: dir)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("wrapper/js/app.js")), big)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("wrapper/manifest.json"), encoding: .utf8), "{\"a\":1}")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("wrapper/empty.txt")).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("__MACOSX").path))
    }

    func testZipSlipRejected() throws {
        let zip = makeZIP([("../evil.txt", Data("x".utf8), false)])
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try ZIPExtractor.unzip(data: zip, to: dir)) { error in
            XCTAssertEqual(error as? ExtensionPackageError, .unsafePath("../evil.txt"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("evil.txt").path))
    }

    func testManifestNormalization() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wrapper = dir.appendingPathComponent("wrapper")
        try FileManager.default.createDirectory(at: wrapper.appendingPathComponent("_locales/en"), withIntermediateDirectories: true)
        let manifest = """
        {"name":"__MSG_extName__","description":"__MSG_extDesc__","version":"1.2.3","manifest_version":2,
         "default_locale":"en","background":{"scripts":["bg.js"],"persistent":true}}
        """
        try manifest.write(to: wrapper.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let messages = """
        {"extName":{"message":"Hello Ext"},"extDesc":{"message":"Does things"}}
        """
        try messages.write(to: wrapper.appendingPathComponent("_locales/en/messages.json"), atomically: true, encoding: .utf8)

        let info = try ManifestNormalizer.prepareExtensionDirectory(at: dir)
        XCTAssertEqual(info.name, "Hello Ext")
        XCTAssertEqual(info.description, "Does things")
        XCTAssertEqual(info.version, "1.2.3")
        XCTAssertEqual(info.manifestVersion, 2)
        XCTAssertTrue(info.wasPatchedForiOS)
        XCTAssertEqual(info.manifestDirectoryURL.lastPathComponent, "wrapper")
        let data = try Data(contentsOf: wrapper.appendingPathComponent("manifest.json"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((obj["background"] as? [String: Any])?["persistent"] as? Bool, false)
    }

    func testManifestMissing() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try ManifestNormalizer.prepareExtensionDirectory(at: dir))
    }

    func testChromeWebStoreURL() {
        let id = "bpoadfkcbjbfhfodiogcnhhhpibjhbnh"
        for input in [id,
                      "https://chromewebstore.google.com/detail/immersive-translate-ai-we/\(id)",
                      "https://chrome.google.com/webstore/detail/immersive-translate/\(id)?hl=en"] {
            let r = ChromeWebStoreURL.crxDownloadURL(from: input)
            XCTAssertEqual(r?.extensionID, id, input)
            XCTAssertTrue(r?.url.absoluteString.contains("x=id%3D\(id)") == true)
        }
        XCTAssertNil(ChromeWebStoreURL.crxDownloadURL(from: "https://example.com/foo.zip"))
    }
}
