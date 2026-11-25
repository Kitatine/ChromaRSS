import Foundation
import Compression

public enum ExtensionPackageError: Error, LocalizedError, Equatable {
    case invalidArchive(String)
    case unsafePath(String)
    case unsupportedCompression(UInt16)
    case manifestNotFound
    case invalidManifest(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let m): return "The extension package is invalid: \(m)"
        case .unsafePath(let p): return "The extension package contains an unsafe path: \(p)"
        case .unsupportedCompression(let c): return "Unsupported ZIP compression method \(c)."
        case .manifestNotFound: return "No manifest.json was found in the package."
        case .invalidManifest(let m): return "The extension manifest is invalid: \(m)"
        }
    }
}

// MARK: - CRX

public enum CRXUnpacker {
    /// Returns the raw ZIP payload from a CRX2 / CRX3 file, or the data itself if it is already a ZIP.
    public static func extractZIPData(fromCRXOrZIP data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count >= 4 else { throw ExtensionPackageError.invalidArchive("file too small") }
        if b[0] == 0x50, b[1] == 0x4B { return data }
        guard b[0] == 0x43, b[1] == 0x72, b[2] == 0x32, b[3] == 0x34 else {
            throw ExtensionPackageError.invalidArchive("not a CRX or ZIP file")
        }
        guard b.count >= 12 else { throw ExtensionPackageError.invalidArchive("truncated CRX header") }
        let version = le32(b, 4)
        let start: Int
        switch version {
        case 3:
            start = 12 + Int(le32(b, 8))
        case 2:
            guard b.count >= 16 else { throw ExtensionPackageError.invalidArchive("truncated CRX2 header") }
            start = 16 + Int(le32(b, 8)) + Int(le32(b, 12))
        default:
            throw ExtensionPackageError.invalidArchive("unsupported CRX version \(version)")
        }
        guard start >= 0, start + 4 <= b.count else { throw ExtensionPackageError.invalidArchive("CRX header exceeds file size") }
        let isLocal = b[start] == 0x50 && b[start + 1] == 0x4B && b[start + 2] == 0x03 && b[start + 3] == 0x04
        let isEmpty = b[start] == 0x50 && b[start + 1] == 0x4B && b[start + 2] == 0x05 && b[start + 3] == 0x06
        guard isLocal || isEmpty else { throw ExtensionPackageError.invalidArchive("CRX payload is not a ZIP archive") }
        return data.subdata(in: (data.startIndex + start)..<data.endIndex)
    }
}

@inline(__always) func le16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | (UInt16(b[o + 1]) << 8) }
@inline(__always) func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
    UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
}

// MARK: - ZIP

public enum ZIPExtractor {
    public static func unzip(data: Data, to destinationDir: URL) throws {
        let b = [UInt8](data)
        guard b.count >= 22 else { throw ExtensionPackageError.invalidArchive("ZIP too small") }

        // End of central directory
        var eocd = -1
        var i = b.count - 22
        let lowest = max(0, b.count - 22 - 65_535)
        while i >= lowest {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ExtensionPackageError.invalidArchive("end of central directory not found") }
        let totalEntries = Int(le16(b, eocd + 10))
        var cursor = Int(le32(b, eocd + 16))

        let fm = FileManager.default
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let rootPath = destinationDir.standardizedFileURL.path

        for _ in 0..<totalEntries {
            guard cursor + 46 <= b.count, le32(b, cursor) == 0x02014b50 else {
                throw ExtensionPackageError.invalidArchive("bad central directory entry")
            }
            let method = le16(b, cursor + 10)
            let cSize = le32(b, cursor + 20)
            let uSize = le32(b, cursor + 24)
            let nameLen = Int(le16(b, cursor + 28))
            let extraLen = Int(le16(b, cursor + 30))
            let commentLen = Int(le16(b, cursor + 32))
            let localOffset = Int(le32(b, cursor + 42))
            guard cursor + 46 + nameLen <= b.count else { throw ExtensionPackageError.invalidArchive("truncated entry name") }
            let rawName = String(decoding: b[(cursor + 46)..<(cursor + 46 + nameLen)], as: UTF8.self)
            cursor += 46 + nameLen + extraLen + commentLen

            let name = rawName.replacingOccurrences(of: "\\", with: "/")
            if name.hasPrefix("__MACOSX/") || name.hasSuffix(".DS_Store") { continue }
            if cSize == 0xFFFF_FFFF || uSize == 0xFFFF_FFFF { throw ExtensionPackageError.invalidArchive("ZIP64 is not supported") }

            let comps = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if name.hasPrefix("/") || comps.contains("..") { throw ExtensionPackageError.unsafePath(rawName) }
            let target = comps.reduce(destinationDir) { $0.appendingPathComponent($1) }
            let targetPath = target.standardizedFileURL.path
            guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { throw ExtensionPackageError.unsafePath(rawName) }

            if name.hasSuffix("/") {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }

            guard localOffset + 30 <= b.count, le32(b, localOffset) == 0x04034b50 else {
                throw ExtensionPackageError.invalidArchive("bad local header for \(rawName)")
            }
            let lNameLen = Int(le16(b, localOffset + 26))
            let lExtraLen = Int(le16(b, localOffset + 28))
            let dataStart = localOffset + 30 + lNameLen + lExtraLen
            let dataEnd = dataStart + Int(cSize)
            guard dataEnd <= b.count else { throw ExtensionPackageError.invalidArchive("entry data out of bounds for \(rawName)") }

            let output: Data
            switch method {
            case 0:
                output = Data(b[dataStart..<dataEnd])
            case 8:
                if uSize == 0 {
                    output = Data()
                } else {
                    let cap = max(Int(uSize) + 64, 1024)
                    var out = [UInt8](repeating: 0, count: cap)
                    let src = Array(b[dataStart..<dataEnd])
                    let n = src.withUnsafeBufferPointer { sp -> Int in
                        guard let base = sp.baseAddress else { return 0 }
                        return compression_decode_buffer(&out, cap, base, sp.count, nil, COMPRESSION_ZLIB)
                    }
                    guard n == Int(uSize) else { throw ExtensionPackageError.invalidArchive("inflate failed for \(rawName)") }
                    output = Data(out[0..<n])
                }
            default:
                throw ExtensionPackageError.unsupportedCompression(method)
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: target)
        }
    }
}

// MARK: - Manifest

public struct NormalizedExtensionInfo: Sendable, Equatable {
    public var manifestDirectoryURL: URL
    public var name: String
    public var version: String
    public var description: String
    public var manifestVersion: Int
    public var wasPatchedForiOS: Bool

    public init(manifestDirectoryURL: URL, name: String, version: String, description: String,
                manifestVersion: Int, wasPatchedForiOS: Bool) {
        self.manifestDirectoryURL = manifestDirectoryURL
        self.name = name
        self.version = version
        self.description = description
        self.manifestVersion = manifestVersion
        self.wasPatchedForiOS = wasPatchedForiOS
    }
}

public enum ManifestNormalizer {
    public static func findManifestDirectory(in root: URL) -> URL? {
        let fm = FileManager.default
        var level = [root]
        for depth in 0...2 {
            var next: [URL] = []
            for dir in level {
                if fm.fileExists(atPath: dir.appendingPathComponent("manifest.json").path) { return dir }
                guard depth < 2, let kids = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
                for k in kids where !k.lastPathComponent.hasPrefix("__MACOSX") {
                    if (try? k.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { next.append(k) }
                }
            }
            level = next
        }
        return nil
    }

    public static func prepareExtensionDirectory(at extractedRoot: URL) throws -> NormalizedExtensionInfo {
        guard let dir = findManifestDirectory(in: extractedRoot) else { throw ExtensionPackageError.manifestNotFound }
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let raw = try Data(contentsOf: manifestURL)
        // Chrome manifests may carry a UTF-8 BOM.
        let cleaned = raw.starts(with: [0xEF, 0xBB, 0xBF]) ? raw.dropFirst(3) : raw[...]
        guard var manifest = (try? JSONSerialization.jsonObject(with: Data(cleaned))) as? [String: Any] else {
            throw ExtensionPackageError.invalidManifest("manifest.json is not a JSON object")
        }

        var patched = false
        if var bg = manifest["background"] as? [String: Any], (bg["persistent"] as? Bool) == true {
            bg["persistent"] = false
            manifest["background"] = bg
            patched = true
        }
        if patched {
            let out = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
            try out.write(to: manifestURL)
        }

        let messages = loadMessages(in: dir, defaultLocale: manifest["default_locale"] as? String)
        func localized(_ v: Any?) -> String {
            guard let s = v as? String else { return "" }
            return localize(s, messages: messages)
        }
        let name = localized(manifest["name"])
        let mv = (manifest["manifest_version"] as? Int) ?? Int((manifest["manifest_version"] as? Double) ?? 0)
        return NormalizedExtensionInfo(
            manifestDirectoryURL: dir,
            name: name.isEmpty ? dir.lastPathComponent : name,
            version: (manifest["version"] as? String) ?? "0",
            description: localized(manifest["description"]),
            manifestVersion: mv,
            wasPatchedForiOS: patched)
    }

    static func loadMessages(in dir: URL, defaultLocale: String?) -> [String: String] {
        guard let locale = defaultLocale else { return [:] }
        let url = dir.appendingPathComponent("_locales/\(locale)/messages.json")
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in obj {
            if let d = v as? [String: Any], let m = d["message"] as? String { result[k.lowercased()] = m }
        }
        return result
    }

    static func localize(_ s: String, messages: [String: String]) -> String {
        guard s.hasPrefix("__MSG_"), s.hasSuffix("__"), s.count > 8 else { return s }
        let key = String(s.dropFirst(6).dropLast(2)).lowercased()
        return messages[key] ?? s
    }
}

// MARK: - Chrome Web Store

public enum ChromeWebStoreURL {
    public static func extensionID(from input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?<![a-z0-9])[a-p]{32}(?![a-z0-9])") else { return nil }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        return matches.last.map { ns.substring(with: $0.range) }
    }

    public static func crxDownloadURL(from input: String) -> (extensionID: String, url: URL)? {
        guard let id = extensionID(from: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let s = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.6778.86&acceptformat=crx2,crx3&x=id%3D\(id)%26installsource%3Dondemand%26uc"
        guard let url = URL(string: s) else { return nil }
        return (id, url)
    }
}
