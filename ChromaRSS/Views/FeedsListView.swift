import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    static var writableContentTypes: [UTType] { [.xml] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct FeedsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeedSyncService.self) private var sync
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Feed.title) private var feeds: [Feed]

    @State private var showAdd = false
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDoc = OPMLDocument(text: "")
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if feeds.isEmpty { emptyState } else { feedList }
            }
            .navigationTitle("Feeds")
            .toolbar {
                ToolbarItem(placement: .chromaLeading) {
                    if sync.isRefreshing { ProgressView() }
                }
                ToolbarItemGroup(placement: .chromaTrailing) {
                    Menu {
                        Button { Task { await sync.refreshAll(feeds: feeds, in: modelContext) } } label: {
                            Label("Refresh All", systemImage: "arrow.clockwise")
                        }
                        Button { importing = true } label: { Label("Import OPML…", systemImage: "square.and.arrow.down") }
                        Button {
                            exportDoc = OPMLDocument(text: sync.exportOPML(feeds: feeds))
                            exporting = true
                        } label: { Label("Export OPML…", systemImage: "square.and.arrow.up") }
                        .disabled(feeds.isEmpty)
                    } label: {
                        Label("Feed Options", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    Button("Add Feed", systemImage: "plus") { showAdd = true }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showAdd) { AddFeedSheet() }
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Subscriptions", systemImage: "newspaper")
        } description: {
            Text("Add a feed, import an OPML file, or start with a few sample feeds (including Japanese and French ones to try translation extensions).")
        } actions: {
            Button("Add Starter Feeds") {
                Task { await sync.addStarterFeeds(preferExtensionBrowser: settings.defaultOpenInExtensionBrowser, in: modelContext) }
            }
            .buttonStyle(.borderedProminent)
            Button("Subscribe to Feed") { showAdd = true }
            Button("Import OPML") { importing = true }
        }
    }

    private var feedList: some View {
        List {
            Section {
                NavigationLink { ArticleListView(scope: .unread, title: "Unread") } label: {
                    Label("Unread", systemImage: "circle.inset.filled")
                }
                NavigationLink { ArticleListView(scope: .starred, title: "Starred") } label: {
                    Label("Starred", systemImage: "star")
                }
                NavigationLink { ArticleListView(scope: .all, title: "All Articles") } label: {
                    Label("All Articles", systemImage: "tray.full")
                }
            }
            let groups = Dictionary(grouping: feeds) { $0.folderName ?? "Feeds" }
            ForEach(groups.keys.sorted(), id: \.self) { folder in
                Section(folder) {
                    ForEach(groups[folder] ?? []) { feed in
                        NavigationLink { ArticleListView(scope: .feed(feed.feedURL), title: feed.title) } label: {
                            HStack {
                                Text(feed.title).lineLimit(1)
                                Spacer()
                                if feed.unreadCount > 0 {
                                    Text("\(feed.unreadCount)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                feed.preferExtensionBrowser.toggle()
                            } label: {
                                Label(feed.preferExtensionBrowser ? "Open in Reader Instead" : "Open in Extension Browser",
                                      systemImage: feed.preferExtensionBrowser ? "doc.text" : "puzzlepiece.extension")
                            }
                            Button(role: .destructive) { modelContext.delete(feed) } label: { Label("Unsubscribe", systemImage: "trash") }
                        }
                        .swipeActions {
                            Button(role: .destructive) { modelContext.delete(feed) } label: { Label("Unsubscribe", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .refreshable { await sync.refreshAll(feeds: feeds, in: modelContext) }
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
    FeedsListView()
        .chromaPreviewEnvironment()
}
