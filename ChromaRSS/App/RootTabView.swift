import SwiftUI

struct RootTabView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ExtensionManager.self) private var manager
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var m = manager
        Group {
            #if os(macOS)
            InoreaderWorkspaceView()
            #else
            if sizeClass == .regular {
                InoreaderWorkspaceView()
            } else {
                compactTabs
                    .sheet(item: $m.optionsRequest) { request in
                        ExtensionOptionsSheet(extensionContext: request.context)
                    }
            }
            #endif
        }
        .environment(\.chromaTheme, settings.readerTheme)
        .environment(\.chromaHeadlineDesign, settings.headlineDesign)
        .preferredColorScheme(settings.readerTheme.colorScheme)
    }

    private var compactTabs: some View {
        TabView {
            Tab("Stream", systemImage: "newspaper.fill") {
                NavigationStack {
                    ArticleListView(scope: .all, title: "ChromaRSS", showEmptyStarterButton: true)
                }
            }
            Tab("Library", systemImage: "square.grid.2x2.fill") {
                FeedsListView()
            }
            Tab("Plugins", systemImage: "puzzlepiece.extension.fill") {
                ExtensionManagerView()
            }
            .badge(manager.enabledRecords.count)
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .chromaPreviewEnvironment()
}
