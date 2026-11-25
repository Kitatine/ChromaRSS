import SwiftUI

struct RootTabView: View {
    @Environment(ExtensionManager.self) private var manager

    var body: some View {
        @Bindable var m = manager
        TabView {
            Tab("Feeds", systemImage: "dot.radiowaves.up.forward") {
                FeedsListView()
            }
            Tab("Extensions", systemImage: "puzzlepiece.extension") {
                ExtensionManagerView()
            }
            .badge(manager.enabledRecords.count)
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .sheet(item: $m.optionsRequest) { request in
            ExtensionOptionsSheet(extensionContext: request.context)
        }
    }
}

#Preview {
    RootTabView()
        .chromaPreviewEnvironment()
}
