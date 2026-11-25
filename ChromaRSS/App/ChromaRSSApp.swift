import SwiftUI
import SwiftData

@main
struct ChromaRSSApp: App {
    @State private var settings: AppSettings
    @State private var extensionManager: ExtensionManager
    @State private var syncService = FeedSyncService()
    private let container: ModelContainer
    private let screenshotOutputDir: String?

    init() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--capture-screenshots"), idx + 1 < args.count {
            screenshotOutputDir = args[idx + 1]
        } else {
            screenshotOutputDir = nil
        }

        let s = AppSettings()
        _settings = State(initialValue: s)
        _extensionManager = State(initialValue: ExtensionManager(settings: s))
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: screenshotOutputDir != nil)
            container = try ModelContainer(for: Feed.self, Article.self, configurations: config)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if os(macOS)
                if let outputDir = screenshotOutputDir {
                    ScreenshotHarnessView(outputDir: outputDir)
                } else {
                    RootTabView()
                        .frame(minWidth: 420, minHeight: 740)
                        .task { await extensionManager.bootstrap() }
                }
                #else
                RootTabView()
                    .task { await extensionManager.bootstrap() }
                #endif
            }
            .environment(settings)
            .environment(extensionManager)
            .environment(syncService)
        }
        .modelContainer(container)
    }
}
