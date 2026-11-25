import SwiftUI
import SwiftData

enum WorkspaceSidebarItem: Hashable {
    case unread
    case today
    case all
    case saved
    case folder(String)
    case feed(String)
    case extensions
    case settings
}

struct InoreaderWorkspaceView: View {
    var initialSelectedArticle: Article? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.chromaTheme) private var theme
    @Environment(AppSettings.self) private var settings
    @Environment(ExtensionManager.self) private var manager
    @Environment(FeedSyncService.self) private var sync

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \Article.sortDate, order: .reverse) private var allArticles: [Article]

    @State private var selection: WorkspaceSidebarItem? = .unread
    @State private var selectedArticle: Article?
    @State private var showAddFeed = false
    @State private var collapsedFolders: Set<String> = []

    var body: some View {
        @Bindable var m = manager
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 255, max: 300)
        } content: {
            middleColumn
                .navigationSplitViewColumnWidth(min: 340, ideal: 410, max: 520)
        } detail: {
            detailColumn
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedSheet { feed in
                let folder = feed.folderName?.nilIfEmpty ?? "Subscriptions"
                collapsedFolders.remove(folder)
                selection = .feed(feed.feedURL)
                if selectedArticle == nil {
                    selectedArticle = feed.articles.sorted(by: { $0.sortDate > $1.sortDate }).first
                }
            }
        }
        .sheet(item: $m.optionsRequest) { request in
            ExtensionOptionsSheet(extensionContext: request.context)
        }
        .onAppear {
            if selectedArticle == nil, let initialSelectedArticle {
                selectedArticle = initialSelectedArticle
            }
        }
    }

    private var sidebar: some View {
        let unreadCount = allArticles.filter { !$0.isRead }.count
        let todayCount = allArticles.filter { Calendar.current.isDateInToday($0.sortDate) }.count
        let savedCount = allArticles.filter(\.isStarred).count
        let groups = Dictionary(grouping: feeds) { ($0.folderName?.nilIfEmpty) ?? "Subscriptions" }

        return List(selection: $selection) {
            Section("Smart Streams") {
                sidebarBadgeRow(title: "Unread", systemImage: "circle.inset.filled", tint: ChromaPalette.unreadIndigo, count: unreadCount)
                    .tag(WorkspaceSidebarItem.unread)
                sidebarBadgeRow(title: "Today", systemImage: "sun.max.fill", tint: ChromaPalette.teal, count: todayCount)
                    .tag(WorkspaceSidebarItem.today)
                sidebarBadgeRow(title: "All Articles", systemImage: "tray.full.fill", tint: ChromaPalette.plum, count: allArticles.count)
                    .tag(WorkspaceSidebarItem.all)
                sidebarBadgeRow(title: "Saved", systemImage: "bookmark.fill", tint: ChromaPalette.starAmber, count: savedCount)
                    .tag(WorkspaceSidebarItem.saved)
            }

            Section {
                if feeds.isEmpty {
                    Button {
                        showAddFeed = true
                    } label: {
                        Label("Subscribe to a Feed…", systemImage: "plus.circle")
                    }
                } else {
                    ForEach(groups.keys.sorted(), id: \.self) { folder in
                        let folderFeeds = groups[folder] ?? []
                        let folderUnread = folderFeeds.reduce(0) { $0 + $1.unreadCount }
                        DisclosureGroup(isExpanded: folderExpandedBinding(for: folder)) {
                            ForEach(folderFeeds) { feed in
                                HStack(spacing: ChromaSpacing.xs) {
                                    FeedAvatarView(title: feed.title, siteURL: feed.siteURL, feedURL: feed.feedURL, iconURL: feed.iconURL, size: 20)
                                    Text(feed.title).lineLimit(1)
                                    Spacer()
                                    if feed.unreadCount > 0 {
                                        Text("\(feed.unreadCount)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(WorkspaceSidebarItem.feed(feed.feedURL))
                            }
                        } label: {
                            HStack {
                                Label(folder, systemImage: "folder.fill")
                                Spacer()
                                if folderUnread > 0 {
                                    Text("\(folderUnread)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(WorkspaceSidebarItem.folder(folder))
                    }
                }
            } header: {
                HStack {
                    Text("Feeds")
                    Spacer()
                    Button {
                        showAddFeed = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(ChromaPalette.unreadIndigo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Feed")
                }
            }

            Section("Workspace") {
                sidebarBadgeRow(
                    title: "Chrome Plugins",
                    systemImage: "puzzlepiece.extension.fill",
                    tint: ChromaPalette.emerald,
                    count: manager.enabledRecords.count
                )
                .tag(WorkspaceSidebarItem.extensions)

                Label("Settings", systemImage: "gearshape.fill")
                    .tag(WorkspaceSidebarItem.settings)
            }
        }
        .navigationTitle("ChromaRSS")
        .toolbar {
            ToolbarItem(placement: .chromaTrailing) {
                Button("Add Feed", systemImage: "plus") { showAddFeed = true }
                    .labelStyle(.iconOnly)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    showAddFeed = true
                } label: {
                    Label("Subscribe to Feed", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
                .padding(ChromaSpacing.s)
            }
            .background(.bar)
        }
        .onChange(of: selection) { _, newValue in
            if case .extensions = newValue { selectedArticle = nil }
            if case .settings = newValue { selectedArticle = nil }
        }
    }

    private func folderExpandedBinding(for folder: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedFolders.contains(folder) },
            set: { expanded in
                if expanded { collapsedFolders.remove(folder) }
                else { collapsedFolders.insert(folder) }
            }
        )
    }

    private func sidebarBadgeRow(title: String, systemImage: String, tint: Color, count: Int) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.elevatedColor, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var middleColumn: some View {
        switch selection ?? .unread {
        case .unread:
            ArticleListView(scope: .unread, title: "Unread", selectedArticle: $selectedArticle, showEmptyStarterButton: true)
        case .today:
            ArticleListView(scope: .today, title: "Today", selectedArticle: $selectedArticle, showEmptyStarterButton: true)
        case .all:
            ArticleListView(scope: .all, title: "All Articles", selectedArticle: $selectedArticle, showEmptyStarterButton: true)
        case .saved:
            ArticleListView(scope: .starred, title: "Saved", selectedArticle: $selectedArticle)
        case .folder(let name):
            ArticleListView(scope: .folder(name), title: name, selectedArticle: $selectedArticle)
        case .feed(let url):
            let feedTitle = feeds.first(where: { $0.feedURL == url })?.title ?? "Feed"
            ArticleListView(scope: .feed(url), title: feedTitle, selectedArticle: $selectedArticle)
        case .extensions:
            ExtensionManagerView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if selection == .extensions {
            ContentUnavailableView(
                "Chrome Plugin Studio",
                systemImage: "puzzlepiece.extension.fill",
                description: Text("Install Immersive Translate or any .crx/.zip plugin on the left, then select an article from any feed to read with it.")
            )
            .background(theme.canvasColor)
        } else if let article = selectedArticle {
            let useExtension = article.feed?.preferExtensionBrowser ?? settings.defaultOpenInExtensionBrowser
            if useExtension, let url = URL(string: article.link) {
                ExtensionBrowserView(target: BrowserTarget(url: url, title: article.title, article: article), isEmbedded: true)
                    .id(article.uniqueKey)
            } else {
                ArticleReaderView(article: article)
                    .id(article.uniqueKey)
            }
        } else {
            ContentUnavailableView {
                Label("Select an Article", systemImage: "newspaper")
            } description: {
                Text("Articles open inside the embedded Chrome-Extension Browser (\(manager.enabledRecords.count) plugin active) so tools like Immersive Translate work directly inline.")
            } actions: {
                if feeds.isEmpty {
                    HStack(spacing: ChromaSpacing.s) {
                        Button("Subscribe to Feed") {
                            showAddFeed = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Load Starter Feeds") {
                            Task { await sync.addStarterFeeds(preferExtensionBrowser: settings.defaultOpenInExtensionBrowser, in: modelContext) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .background(theme.canvasColor)
        }
    }
}

#Preview {
    InoreaderWorkspaceView()
        .chromaPreviewEnvironment()
        .frame(width: 1180, height: 760)
}
