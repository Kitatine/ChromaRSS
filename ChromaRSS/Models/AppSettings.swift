import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let openInExtension = "defaultOpenInExtensionBrowser"
        static let autoGrant = "autoGrantExtensionPermissions"
        static let seededBundled = "hasSeededBundledExtension"
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

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [Key.openInExtension: true, Key.autoGrant: true, Key.seededBundled: false])
        defaultOpenInExtensionBrowser = d.bool(forKey: Key.openInExtension)
        autoGrantExtensionPermissions = d.bool(forKey: Key.autoGrant)
        hasSeededBundledExtension = d.bool(forKey: Key.seededBundled)
    }
}
