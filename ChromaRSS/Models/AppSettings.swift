import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let openInExtension = "defaultOpenInExtensionBrowser"
        static let autoGrant = "autoGrantExtensionPermissions"
        static let seededBundled = "hasSeededBundledExtension"
        static let seededFeeds = "hasSeededStarterFeeds"
        static let streamLayout = "streamLayoutMode"
        static let readerTheme = "readerTheme"
        static let headlineDesign = "headlineDesign"
    }

    var defaultOpenInExtensionBrowser: Bool {
        didSet { UserDefaults.standard.set(defaultOpenInExtensionBrowser, forKey: Key.openInExtension) }
    }
    var autoGrantExtensionPermissions: Bool {
        didSet { UserDefaults.standard.set(autoGrantExtensionPermissions, forKey: Key.autoGrant) }
    }
    var hasSeededBundledExtension: Bool {
        didSet { UserDefaults.standard.set(hasSeededBundledExtension, forKey: Key.seededBundled) }
    }
    var hasSeededStarterFeeds: Bool {
        didSet { UserDefaults.standard.set(hasSeededStarterFeeds, forKey: Key.seededFeeds) }
    }
    var streamLayout: StreamLayoutMode {
        didSet { UserDefaults.standard.set(streamLayout.rawValue, forKey: Key.streamLayout) }
    }
    var readerTheme: ReaderTheme {
        didSet { UserDefaults.standard.set(readerTheme.rawValue, forKey: Key.readerTheme) }
    }
    var headlineDesign: HeadlineDesign {
        didSet { UserDefaults.standard.set(headlineDesign.rawValue, forKey: Key.headlineDesign) }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Key.openInExtension: true,
            Key.autoGrant: true,
            Key.seededBundled: false,
            Key.seededFeeds: false,
            Key.streamLayout: StreamLayoutMode.magazine.rawValue,
            Key.readerTheme: ReaderTheme.system.rawValue,
            Key.headlineDesign: HeadlineDesign.serif.rawValue
        ])
        defaultOpenInExtensionBrowser = d.bool(forKey: Key.openInExtension)
        autoGrantExtensionPermissions = d.bool(forKey: Key.autoGrant)
        hasSeededBundledExtension = d.bool(forKey: Key.seededBundled)
        hasSeededStarterFeeds = d.bool(forKey: Key.seededFeeds)
        streamLayout = StreamLayoutMode(rawValue: d.string(forKey: Key.streamLayout) ?? "") ?? .magazine
        readerTheme = ReaderTheme(rawValue: d.string(forKey: Key.readerTheme) ?? "") ?? .system
        headlineDesign = HeadlineDesign(rawValue: d.string(forKey: Key.headlineDesign) ?? "") ?? .serif
    }
}
