import SwiftUI
import SwiftData

struct FeedsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.chromaTheme) private var theme
    @Environment(FeedSyncService.self) private var sync
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \Article.sortDate, order: .reverse) private var allArticles: [Article]

    @State private var showAdd = false
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDoc = OPMLDocument(text: "")
    @State private var message: String?
    @State private var collapsedFolders: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if feeds.isEmpty {
                    emptyState
                } else {
                    feedsDashboard
                }
            }
            .background(theme.canvasColor.ignoresSafeArea())
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .chromaLeading) {
                    if sync.isRefreshing { ProgressView() }
                }
                ToolbarItemGroup(placement: .chromaTrailing) {
                    AppearanceMenuButton()
                    Menu {
                        Button { Task { await sync.refreshAll(feeds: feeds, in: modelContext) } } label: {
                            Label("Refresh All Feeds", systemImage: "arrow.clockwise")
                        }
                        Button { importing = true } label: {
                            Label("Import OPML…", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportDoc = OPMLDocument(text: sync.exportOPML(feeds: feeds))
                            exporting = true
                        } label: {
                            Label("Export OPML…", systemImage: "square.and.arrow.up")
                        }
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
        ScrollView {
            VStack(spacing: ChromaSpacing.l) {
                VStack(spacing: ChromaSpacing.s) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(ChromaPalette.heroGradient, in: RoundedRectangle(cornerRadius: ChromaRadius.xl))
                        .accessibilityHidden(true)

                    Text("Your Reading Workspace")
                        .font(.title2.bold())
                    Text("Subscribe to blogs, news, and foreign-language feeds. Every article opens with your Chrome extensions ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, ChromaSpacing.xl)

                VStack(spacing: ChromaSpacing.s) {
                    Button {
                        Task { await sync.addStarterFeeds(preferExtensionBrowser: settings.defaultOpenInExtensionBrowser, in: modelContext) }
                    } label: {
                        Label("Add Starter Feeds (Includes Bilingual Feeds)", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack(spacing: ChromaSpacing.s) {
                        Button { showAdd = true } label: {
                            Label("Subscribe URL", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button { importing = true } label: {
                            Label("Import OPML", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .padding(ChromaSpacing.l)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var feedsDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChromaSpacing.l) {
                smartGrid
                subscriptionsSection
            }
            .padding(ChromaSpacing.m)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await sync.refreshAll(feeds: feeds, in: modelContext) }
    }

    private var smartGrid: some View {
        let unreadCount = allArticles.filter { !$0.isRead }.count
        let todayCount = allArticles.filter { Calendar.current.isDateInToday($0.sortDate) }.count
        let savedCount = allArticles.filter(\.isStarred).count
        let columns = [GridItem(.flexible(), spacing: ChromaSpacing.s), GridItem(.flexible(), spacing: ChromaSpacing.s)]

        return LazyVGrid(columns: columns, spacing: ChromaSpacing.s) {
            NavigationLink {
                ArticleListView(scope: .unread, title: "Unread")
            } label: {
                SmartStreamTile(title: "Unread", subtitle: "Waiting to read", systemImage: "circle.inset.filled",
                                tint: ChromaPalette.unreadIndigo, count: unreadCount)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ArticleListView(scope: .today, title: "Today")
            } label: {
                SmartStreamTile(title: "Today", subtitle: "Fresh stories", systemImage: "sun.max.fill",
                                tint: ChromaPalette.teal, count: todayCount)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ArticleListView(scope: .starred, title: "Saved")
            } label: {
                SmartStreamTile(title: "Saved", subtitle: "Bookmarks", systemImage: "bookmark.fill",
                                tint: ChromaPalette.starAmber, count: savedCount)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ArticleListView(scope: .all, title: "All Articles")
            } label: {
                SmartStreamTile(title: "All Articles", subtitle: "\(feeds.count) feeds", systemImage: "tray.full.fill",
                                tint: ChromaPalette.plum, count: allArticles.count)
            }
            .buttonStyle(.plain)
        }
    }

    private var subscriptionsSection: some View {
        let groups = Dictionary(grouping: feeds) { ($0.folderName?.nilIfEmpty) ?? "Subscriptions" }
        let sortedFolders = groups.keys.sorted()

        return VStack(alignment: .leading, spacing: ChromaSpacing.m) {
            ForEach(sortedFolders, id: \.self) { folder in
                let folderFeeds = groups[folder] ?? []
                let folderUnread = folderFeeds.reduce(0) { $0 + $1.unreadCount }
                let isCollapsed = collapsedFolders.contains(folder)

                VStack(spacing: 0) {
                    HStack(spacing: ChromaSpacing.xs) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                if isCollapsed { collapsedFolders.remove(folder) } else { collapsedFolders.insert(folder) }
                            }
                        } label: {
                            HStack(spacing: ChromaSpacing.xs) {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(ChromaPalette.unreadIndigo)
                                Text(folder)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        NavigationLink {
                            ArticleListView(scope: .folder(folder), title: folder)
                        } label: {
                            HStack(spacing: 4) {
                                if folderUnread > 0 {
                                    Text("\(folderUnread)")
                                        .font(.caption.bold())
                                        .foregroundStyle(ChromaPalette.unreadIndigo)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(ChromaPalette.unreadIndigo.opacity(0.14), in: Capsule())
                                }
                                Image(systemName: "chevron.forward.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, ChromaSpacing.m)
                    .padding(.vertical, ChromaSpacing.s)

                    if !isCollapsed {
                        Divider()
                        ForEach(Array(folderFeeds.enumerated()), id: \.element.id) { index, feed in
                            NavigationLink {
                                ArticleListView(scope: .feed(feed.feedURL), title: feed.title)
                            } label: {
                                feedRow(feed)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    feed.preferExtensionBrowser.toggle()
                                } label: {
                                    Label(feed.preferExtensionBrowser ? "Open in Reader Instead" : "Open in Extension Browser",
                                          systemImage: feed.preferExtensionBrowser ? "doc.text" : "puzzlepiece.extension")
                                }
                                Button(role: .destructive) { modelContext.delete(feed) } label: {
                                    Label("Unsubscribe", systemImage: "trash")
                                }
                            }
                            if index < folderFeeds.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
                .chromaCardSurface(theme: theme, cornerRadius: ChromaRadius.l)
            }
        }
    }

    private func feedRow(_ feed: Feed) -> some View {
        HStack(spacing: ChromaSpacing.s) {
            FeedAvatarView(title: feed.title, siteURL: feed.siteURL, feedURL: feed.feedURL, iconURL: feed.iconURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let host = URL(string: feed.siteURL ?? feed.feedURL)?.host {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.elevatedColor, in: Capsule())
            }
        }
        .padding(.horizontal, ChromaSpacing.m)
        .padding(.vertical, ChromaSpacing.s)
        .contentShape(Rectangle())
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
