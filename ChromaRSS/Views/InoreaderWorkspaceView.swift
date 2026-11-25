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
            if selectedArticle == nil {
                selectedArticle = initialSelectedArticle
                    ?? allArticles.first(where: { !$0.isRead })
                    ?? allArticles.first
            }
        }
        .onChange(of: allArticles.count) { _, _ in
            if selectedArticle == nil {
                selectedArticle = initialSelectedArticle
                    ?? allArticles.first(where: { !$0.isRead })
                    ?? allArticles.first
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
                        let isCollapsed = collapsedFolders.contains(folder)

                        HStack(spacing: ChromaSpacing.xs) {
                            Button {
                                if isCollapsed { collapsedFolders.remove(folder) }
                                else { collapsedFolders.insert(folder) }
                            } label: {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, height: 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)

                            Image(systemName: "folder.fill")
                                .foregroundStyle(ChromaPalette.unreadIndigo)
                            Text(folder)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            if folderUnread > 0 {
                                Text("\(folderUnread)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .tag(WorkspaceSidebarItem.folder(folder))

                        if !isCollapsed {
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
                                .padding(.leading, 18)
                                .contentShape(Rectangle())
                                .tag(WorkspaceSidebarItem.feed(feed.feedURL))
                                .contextMenu {
                                    Button {
                                        Task { try? await sync.refresh(feed: feed, in: modelContext) }
                                    } label: {
                                        Label("Refresh Feed", systemImage: "arrow.clockwise")
                                    }
                                    Button {
                                        feed.preferExtensionBrowser.toggle()
                                    } label: {
                                        Label(feed.preferExtensionBrowser ? "Default to Reader View" : "Default to Extension Browser",
                                              systemImage: feed.preferExtensionBrowser ? "doc.text" : "puzzlepiece.extension")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        if selection == .feed(feed.feedURL) { selection = .all }
                                        modelContext.delete(feed)
                                    } label: {
                                        Label("Unsubscribe", systemImage: "trash")
                                    }
                                }
                            }
                        }
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
                    .contentShape(Rectangle())
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
            switch newValue {
            case .extensions, .settings:
                selectedArticle = nil
            case .feed(let url):
                if selectedArticle?.feedURL != url {
                    selectedArticle = allArticles.first(where: { $0.feedURL == url && !$0.isRead })
                        ?? allArticles.first(where: { $0.feedURL == url })
                }
            case .folder(let name):
                let currentFolder = selectedArticle?.feed?.folderName?.nilIfEmpty ?? "Subscriptions"
                if selectedArticle == nil || currentFolder != name {
                    selectedArticle = allArticles.first(where: { ($0.feed?.folderName?.nilIfEmpty ?? "Subscriptions") == name && !$0.isRead })
                        ?? allArticles.first(where: { ($0.feed?.folderName?.nilIfEmpty ?? "Subscriptions") == name })
                }
            default:
                break
            }
        }
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
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var middleColumn: some View {
        Group {
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
        .id(selection)
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
            if useExtension, let url = article.resolvedURL {
                ExtensionBrowserView(target: BrowserTarget(url: url, title: article.title, article: article), isEmbedded: true)
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
