import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import WebKit
import Observation
import ChromaRSSCore

struct InstalledExtensionRecord: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var version: String
    var descriptionText: String
    var manifestVersion: Int
    /// Path from `Extensions/<id>/` to the folder containing manifest.json ("" when at the root).
    var manifestRelativePath: String
    var isEnabled: Bool
    var wasPatchedForiOS: Bool
    var isBundled: Bool
    var installedAt: Date
}

enum ExtensionInstallError: LocalizedError {
    case invalidInput
    case download(String)
    case notAPackage
    case loadFailed(String)
    case noActiveBrowser

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Enter a Chrome Web Store link, an extension ID, or a direct .crx/.zip URL."
        case .download(let m):
            return "Download failed: \(m)"
        case .notAPackage:
            return "The server didn't return an extension package (Chrome Web Store may be blocked on this network). Download the extension's .zip from its GitHub Releases page and import it from Files instead."
        case .loadFailed(let m):
            return "WebKit couldn't load this extension: \(m)"
        case .noActiveBrowser:
            return "No browser window is open."
        }
    }
}

struct OptionsRequest: Identifiable {
    let id = UUID()
    let context: WKWebExtensionContext
}

@MainActor
@Observable
final class ExtensionManager: NSObject, WKWebExtensionControllerDelegate {
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    static let bundledID = "chromarss-bilingual-helper"

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored weak var activeSession: BrowserSession?
    @ObservationIgnored private var didBootstrap = false

    private(set) var records: [InstalledExtensionRecord] = []
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    private(set) var loadErrors: [String: String] = [:]
    /// Bumped whenever an extension action changes so toolbars refresh.
    private(set) var revision = 0
    var optionsRequest: OptionsRequest?

    init(settings: AppSettings) {
        self.settings = settings
        self.controller = WKWebExtensionController(configuration: .default())
        super.init()
        controller.delegate = self
    }

    // MARK: Paths

    private var extensionsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ChromaRSS/Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var registryURL: URL { extensionsDir.appendingPathComponent("registry.json") }

    private func directory(for record: InstalledExtensionRecord) -> URL {
        var url = extensionsDir.appendingPathComponent(record.id, isDirectory: true)
        if !record.manifestRelativePath.isEmpty { url = url.appendingPathComponent(record.manifestRelativePath, isDirectory: true) }
        return url
    }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL),
              let decoded = try? JSONDecoder().decode([InstalledExtensionRecord].self, from: data) else { return }
        records = decoded
    }

    private func saveRegistry() {
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: registryURL, options: .atomic) }
    }

    // MARK: Bootstrap

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        loadRegistry()
        if !settings.hasSeededBundledExtension || (!records.contains(where: { $0.isBundled }) && !settings.hasSeededBundledExtension) {
            await seedBundledExtension()
        }
        for record in records where record.isEnabled {
            do { try await load(record: record) } catch { loadErrors[record.id] = error.localizedDescription }
        }
    }

    func restoreBundledExtension() async {
        if let existing = records.first(where: { $0.isBundled }) { try? removeExtension(id: existing.id) }
        await seedBundledExtension()
        if let record = records.first(where: { $0.isBundled }) {
            do { try await load(record: record) } catch { loadErrors[record.id] = error.localizedDescription }
        }
    }

    private func seedBundledExtension() async {
        guard let src = Bundle.main.url(forResource: "bilingual-helper", withExtension: nil) else { return }
        let dest = extensionsDir.appendingPathComponent(Self.bundledID, isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            let info = try ManifestNormalizer.prepareExtensionDirectory(at: dest)
            let record = InstalledExtensionRecord(
                id: Self.bundledID, name: info.name, version: info.version, descriptionText: info.description,
                manifestVersion: info.manifestVersion, manifestRelativePath: relativePath(of: info.manifestDirectoryURL, in: dest),
                isEnabled: true, wasPatchedForiOS: info.wasPatchedForiOS, isBundled: true, installedAt: Date())
            records.removeAll { $0.id == record.id }
            records.append(record)
            saveRegistry()
            settings.hasSeededBundledExtension = true
        } catch {
            loadErrors[Self.bundledID] = error.localizedDescription
        }
    }

    private func relativePath(of dir: URL, in root: URL) -> String {
        let d = dir.standardizedFileURL.path, r = root.standardizedFileURL.path
        guard d.hasPrefix(r) else { return "" }
        return String(d.dropFirst(r.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: Load / unload

    private func grantAll(_ ctx: WKWebExtensionContext, _ ext: WKWebExtension) {
        for perm in ext.requestedPermissions { ctx.setPermissionStatus(.grantedExplicitly, for: perm) }
        for pattern in ext.requestedPermissionMatchPatterns { ctx.setPermissionStatus(.grantedExplicitly, for: pattern) }
        ctx.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.MatchPattern.allURLs())
    }

    private func load(record: InstalledExtensionRecord) async throws {
        let ext = try await WKWebExtension(resourceBaseURL: directory(for: record))
        let ctx = WKWebExtensionContext(for: ext)
        // Stable identity: keeps chrome.storage / settings across launches.
        ctx.uniqueIdentifier = record.id
        ctx.isInspectable = true
        ctx.inspectionName = record.name
        if settings.autoGrantExtensionPermissions { grantAll(ctx, ext) }
        try controller.load(ctx)
        contexts[record.id] = ctx
        loadErrors[record.id] = nil
        if ext.hasBackgroundContent {
            Task { try? await ctx.loadBackgroundContent() }
        }
        revision += 1
    }

    private func unload(id: String) {
        if let ctx = contexts[id] { try? controller.unload(ctx) }
        contexts[id] = nil
        revision += 1
    }

    func setEnabled(_ enabled: Bool, for id: String) async {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].isEnabled = enabled
        saveRegistry()
        if enabled {
            do { try await load(record: records[idx]) } catch { loadErrors[id] = error.localizedDescription }
        } else {
            unload(id: id)
        }
    }

    func reload(id: String) async {
        guard let record = records.first(where: { $0.id == id }), record.isEnabled else { return }
        unload(id: id)
        do { try await load(record: record) } catch { loadErrors[id] = error.localizedDescription }
    }

    func removeExtension(id: String) throws {
        unload(id: id)
        try? FileManager.default.removeItem(at: extensionsDir.appendingPathComponent(id, isDirectory: true))
        records.removeAll { $0.id == id }
        loadErrors[id] = nil
        saveRegistry()
    }

    // MARK: Install

    nonisolated private static func unpack(data: Data, to staging: URL) async throws -> NormalizedExtensionInfo {
        let zip = try CRXUnpacker.extractZIPData(fromCRXOrZIP: data)
        try ZIPExtractor.unzip(data: zip, to: staging)
        return try ManifestNormalizer.prepareExtensionDirectory(at: staging)
    }

    @discardableResult
    func installFromFile(url: URL) async throws -> InstalledExtensionRecord {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try await install(packageData: data)
    }

    @discardableResult
    func installFromRemoteInput(_ input: String) async throws -> InstalledExtensionRecord {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if let cws = ChromeWebStoreURL.crxDownloadURL(from: trimmed) {
            url = cws.url
        } else if let u = URL(string: trimmed), ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            url = u
        } else {
            throw ExtensionInstallError.invalidInput
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        req.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ExtensionInstallError.download("HTTP \(http.statusCode)")
            }
            data = d
        } catch let e as ExtensionInstallError {
            throw e
        } catch {
            throw ExtensionInstallError.download(error.localizedDescription)
        }
        guard data.count > 4, data.starts(with: [0x43, 0x72, 0x32, 0x34]) || data.starts(with: [0x50, 0x4B]) else {
            throw ExtensionInstallError.notAPackage
        }
        return try await install(packageData: data)
    }

    private func install(packageData: Data) async throws -> InstalledExtensionRecord {
        let staging = extensionsDir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let info = try await Self.unpack(data: packageData, to: staging)

        // Re-installing an extension with the same name keeps its identity (and therefore its stored settings).
        let existing = records.first(where: { $0.name == info.name && !$0.isBundled })
        let id = existing?.id ?? UUID().uuidString.lowercased()
        if let existing { unload(id: existing.id) }
        let finalDir = extensionsDir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: finalDir)
        let relative = relativePath(of: info.manifestDirectoryURL, in: staging)
        try FileManager.default.moveItem(at: staging, to: finalDir)

        let record = InstalledExtensionRecord(
            id: id, name: info.name, version: info.version, descriptionText: info.description,
            manifestVersion: info.manifestVersion, manifestRelativePath: relative, isEnabled: true,
            wasPatchedForiOS: info.wasPatchedForiOS, isBundled: false, installedAt: Date())
        do {
            try await load(record: record)
        } catch {
            try? FileManager.default.removeItem(at: finalDir)
            records.removeAll { $0.id == id }
            saveRegistry()
            throw ExtensionInstallError.loadFailed(error.localizedDescription)
        }
        records.removeAll { $0.id == id }
        records.append(record)
        saveRegistry()
        return record
    }

    // MARK: Actions

    func performAction(for id: String, in tab: BrowserTabAdapter?) {
        guard let ctx = contexts[id] else { return }
        ctx.performAction(for: tab)
    }

    func openOptions(for id: String) {
        guard let ctx = contexts[id] else { return }
        if let session = activeSession, let url = ctx.optionsPageURL {
            session.openTab(url: url, activate: true)
        } else {
            optionsRequest = OptionsRequest(context: ctx)
        }
    }

    func icon(for id: String, size: CGFloat = 28) -> PlatformImage? {
        let s = CGSize(width: size, height: size)
        if let ctx = contexts[id], let img = ctx.action(for: nil)?.icon(for: s) { return img }
        return contexts[id]?.webExtension.icon(for: s)
    }

    func badge(for id: String, tab: BrowserTabAdapter?) -> String {
        contexts[id]?.action(for: tab)?.badgeText ?? ""
    }

    var enabledRecords: [InstalledExtensionRecord] { records.filter { $0.isEnabled && contexts[$0.id] != nil } }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        activeSession.map { [$0.window] } ?? []
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        activeSession?.window
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let session = activeSession else {
            completionHandler(nil, ExtensionInstallError.noActiveBrowser)
            return
        }
        let tab = session.openTab(url: configuration.url, activate: configuration.shouldBeActive)
        completionHandler(tab, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        if let session = activeSession, let url = extensionContext.optionsPageURL {
            session.openTab(url: url, activate: true)
        } else {
            optionsRequest = OptionsRequest(context: extensionContext)
        }
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        guard settings.autoGrantExtensionPermissions else { completionHandler([], nil); return }
        for p in permissions { extensionContext.setPermissionStatus(.grantedExplicitly, for: p) }
        completionHandler(permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        guard settings.autoGrantExtensionPermissions else { completionHandler([], nil); return }
        for u in urls { extensionContext.setPermissionStatus(.grantedExplicitly, for: u) }
        completionHandler(urls, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        guard settings.autoGrantExtensionPermissions else { completionHandler([], nil); return }
        for p in matchPatterns { extensionContext.setPermissionStatus(.grantedExplicitly, for: p) }
        completionHandler(matchPatterns, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        revision += 1
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        #if os(iOS)
        guard let vc = action.popupViewController, let top = Self.topViewController() else {
            completionHandler(nil)
            return
        }
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        top.present(vc, animated: true) { completionHandler(nil) }
        #elseif os(macOS)
        if let popover = action.popupPopover,
           let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first,
           let contentView = window.contentView {
            popover.show(relativeTo: CGRect(x: contentView.bounds.midX - 1, y: 44, width: 2, height: 2),
                         of: contentView, preferredEdge: .maxY)
        }
        completionHandler(nil)
        #endif
    }

    #if os(iOS)
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif
}
