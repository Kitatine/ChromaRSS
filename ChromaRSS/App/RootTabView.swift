import SwiftUI

struct RootTabView: View {
    @Environment(ExtensionManager.self) private var manager

    var body: some View {
        @Bindable var m = manager
        TabView {
            FeedsListView()
                .tabItem { Label("Feeds", systemImage: "dot.radiowaves.up.forward") }
            ExtensionManagerView()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
                .badge(manager.enabledRecords.count)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(item: $m.optionsRequest) { request in
            ExtensionOptionsSheet(extensionContext: request.context)
        }
    }
}
