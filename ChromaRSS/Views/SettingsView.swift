import SwiftUI
import SwiftData
import WebKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ExtensionManager.self) private var manager
    @Environment(FeedSyncService.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]

    @State private var importing = false
    @State private var exporting = false
    @State private var exportDoc = OPMLDocument(text: "")
    @State private var message: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Open articles in extension browser", isOn: $settings.defaultOpenInExtensionBrowser)
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Applies to newly added feeds. Long-press a feed to change it individually.")
                }
                Section {
                    Toggle("Auto-grant extension permissions", isOn: $settings.autoGrantExtensionPermissions)
                    Button("Restore Built-in Helper Extension") { Task { await manager.restoreBundledExtension() } }
                } header: {
                    Text("Extensions")
                } footer: {
                    Text("Granting access to all websites lets extensions such as translators work without prompts. Takes effect the next time an extension loads.")
                }
                Section("Subscriptions") {
                    Button("Import OPML…") { importing = true }
                    Button("Export OPML…") {
                        exportDoc = OPMLDocument(text: sync.exportOPML(feeds: feeds))
                        exporting = true
                    }
                    .disabled(feeds.isEmpty)
                }
                Section {
                    Button("Clear Website Cache") {
                        Task {
                            let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
                            await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast)
                            message = "Website cache cleared. Extension settings were kept."
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.xml, .plainText, .data]) { result in
                Task { await importOPML(result) }
            }
            .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .xml,
                          defaultFilename: "ChromaRSS-Subscriptions.opml") { _ in }
            .alert("ChromaRSS", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private func importOPML(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let n = try await sync.importOPML(data: data, preferExtensionBrowser: settings.defaultOpenInExtensionBrowser, in: modelContext)
            message = "Imported \(n) new feed(s)."
        } catch {
            message = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .chromaPreviewEnvironment()
}
