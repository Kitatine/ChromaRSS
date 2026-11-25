import SwiftUI
import SwiftData
import ChromaRSSCore

struct BrowserTarget: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let article: Article?
}

struct ArticleListView: View {
    enum Scope: Hashable {
        case all, unread, starred, today
        case folder(String)
        case feed(String)
    }

    let scope: Scope
    let title: String
    var selectedArticle: Binding<Article?>? = nil
    var showEmptyStarterButton: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.chromaTheme) private var theme
    @Environment(FeedSyncService.self) private var sync
    @Environment(AppSettings.self) private var settings
    @Query private var articles: [Article]

    @State private var search = ""
    @State private var filter: StreamFilter = .all
    @State private var browserTarget: BrowserTarget?
    @State private var readerArticle: Article?
    @State private var showAddFeed = false

    init(scope: Scope, title: String, selectedArticle: Binding<Article?>? = nil, showEmptyStarterButton: Bool = false) {
        self.scope = scope
        self.title = title
        self.selectedArticle = selectedArticle
        self.showEmptyStarterButton = showEmptyStarterButton
        let sort = [SortDescriptor(\Article.sortDate, order: .reverse)]
        switch scope {
        case .all, .today, .folder, .unread:
            _articles = Query(sort: sort)
        case .starred:
            _articles = Query(filter: #Predicate<Article> { $0.isStarred }, sort: sort)
        case .feed(let url):
            _articles = Query(filter: #Predicate<Article> { $0.feedURL == url }, sort: sort)
        }
    }

    private var scopedArticles: [Article] {
        switch scope {
        case .unread:
            let activeKey = selectedArticle?.wrappedValue?.uniqueKey
            return articles.filter { !$0.isRead || $0.uniqueKey == activeKey }
        case .today:
            return articles.filter { Calendar.current.isDateInToday($0.sortDate) }
        case .folder(let name):
            return articles.filter { ($0.feed?.folderName?.nilIfEmpty ?? "Subscriptions") == name }
        default:
            return articles
        }
    }

    private var visible: [Article] {
        let activeKey = selectedArticle?.wrappedValue?.uniqueKey
        return scopedArticles.filter { article in
            switch filter {
            case .all: true
            case .unread: !article.isRead || article.uniqueKey == activeKey
            case .saved: article.isStarred
            case .today: Calendar.current.isDateInToday(article.sortDate)
            }
        }
        .filter {
            search.isEmpty ||
            $0.title.localizedStandardContains(search) ||
            ($0.summary ?? "").localizedStandardContains(search)
        }
    }

    private var unreadCount: Int {
        scopedArticles.filter { !$0.isRead }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            if !scopedArticles.isEmpty {
                FilterPillBar(selection: $filter, unreadCount: unreadCount)
                    .background(theme.canvasColor)
            }

            if let err = sync.lastError {
                HStack(spacing: ChromaSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ChromaPalette.coral)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        sync.lastError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss Error")
                }
                .padding(.horizontal, ChromaSpacing.m)
                .padding(.vertical, ChromaSpacing.xs)
                .background(ChromaPalette.coral.opacity(0.12))
            }

            ScrollView {
                if visible.isEmpty {
                    emptyView
                        .padding(.top, 48)
                } else {
                    LazyVStack(spacing: settings.streamLayout == .compact ? ChromaSpacing.xs : ChromaSpacing.s) {
                        ForEach(visible) { article in
                            Group {
                                if settings.streamLayout == .cards {
                                    HeroCardArticleView(
                                        article: article,
                                        isSelected: selectedArticle?.wrappedValue?.uniqueKey == article.uniqueKey,
                                        onOpen: { open(article) },
                                        onToggleRead: { article.isRead.toggle() },
                                        onToggleStar: { article.isStarred.toggle() }
                                    )
                                } else {
                                    Button { open(article) } label: {
                                        rowView(for: article)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .contextMenu { articleActions(article) }
                            .swipeActions(edge: .leading) {
                                Button { article.isStarred.toggle() } label: {
                                    Label(article.isStarred ? "Unsave" : "Save",
                                          systemImage: article.isStarred ? "bookmark.slash" : "bookmark")
                                }
                                .tint(ChromaPalette.starAmber)
                            }
                            .swipeActions(edge: .trailing) {
                                Button { article.isRead.toggle() } label: {
                                    Label(article.isRead ? "Unread" : "Read",
                                          systemImage: article.isRead ? "circle" : "checkmark")
                                }
                                .tint(ChromaPalette.unreadIndigo)
                            }
                        }
                    }
                    .padding(.horizontal, ChromaSpacing.m)
                    .padding(.vertical, ChromaSpacing.xs)
                }
            }
            .background(theme.canvasColor)
        }
        .background(theme.canvasColor.ignoresSafeArea())
        .navigationTitle(title)
        .chromaInlineTitle()
        .searchable(text: $search, prompt: "Search articles")
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .chromaTrailing) {
                Button("Add Feed", systemImage: "plus") { showAddFeed = true }
                    .labelStyle(.iconOnly)
                AppearanceMenuButton()
                Menu {
                    Button { showAddFeed = true } label: {
                        Label("Subscribe to Feed…", systemImage: "plus.circle")
                    }
                    Divider()
                    Button {
                        for article in scopedArticles { article.isRead = true }
                    } label: {
                        Label("Mark All as Read", systemImage: "checkmark.circle")
                    }
                    Button { Task { await refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Label("Stream Options", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showAddFeed) { AddFeedSheet() }
        .chromaBrowserPresentation(item: $browserTarget) { ExtensionBrowserView(target: $0) }
        .navigationDestination(item: $readerArticle) { ArticleReaderView(article: $0) }
    }

    @ViewBuilder
    private func rowView(for article: Article) -> some View {
        let isSelected = selectedArticle?.wrappedValue?.uniqueKey == article.uniqueKey
        switch settings.streamLayout {
        case .magazine:
            MagazineArticleRow(article: article, isSelected: isSelected)
        case .cards:
            HeroCardArticleView(
                article: article,
                isSelected: isSelected,
                onToggleRead: { article.isRead.toggle() },
                onToggleStar: { article.isStarred.toggle() }
            )
        case .compact:
            CompactArticleRow(article: article, isSelected: isSelected)
        }
    }

    @ViewBuilder
    private func articleActions(_ article: Article) -> some View {
        Button {
            article.isRead.toggle()
        } label: {
            Label(article.isRead ? "Mark as Unread" : "Mark as Read",
                  systemImage: article.isRead ? "circle" : "checkmark.circle")
        }
        Button {
            article.isStarred.toggle()
        } label: {
            Label(article.isStarred ? "Remove Bookmark" : "Save for Later",
                  systemImage: article.isStarred ? "bookmark.slash" : "bookmark")
        }
        if let url = article.resolvedURL {
            Button {
                browserTarget = BrowserTarget(url: url, title: article.title, article: article)
            } label: {
                Label("Open in Extension Browser", systemImage: "puzzlepiece.extension")
            }
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        if sync.isRefreshing {
            ContentUnavailableView {
                VStack(spacing: ChromaSpacing.s) {
                    ProgressView()
                    Text("Loading articles…")
                }
            } description: {
                Text("Fetching your subscribed feeds.")
            }
        } else if !search.isEmpty {
            ContentUnavailableView.search
        } else if showEmptyStarterButton && scopedArticles.isEmpty {
            ContentUnavailableView {
                Label("Your Stream is Empty", systemImage: "newspaper")
            } description: {
                Text("Load starter feeds—including tech blogs and foreign-language sites—to start reading with Chrome extensions.")
            } actions: {
                VStack(spacing: ChromaSpacing.xs) {
                    Button("Subscribe to URL…") {
                        showAddFeed = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Add Starter Feeds") {
                        Task { await sync.addStarterFeeds(preferExtensionBrowser: settings.defaultOpenInExtensionBrowser, in: modelContext) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if case .feed = scope {
            ContentUnavailableView {
                Label("No Articles Yet", systemImage: "tray")
            } description: {
                Text("This feed doesn't have any loaded articles yet.")
            } actions: {
                Button("Refresh Feed") {
                    Task { await refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView("No Matching Articles", systemImage: "tray", description: Text("Try switching filters or pulling down to refresh."))
        }
    }

    private func open(_ article: Article) {
        article.isRead = true
        if let selectedArticle {
            selectedArticle.wrappedValue = article
            return
        }
        let useExtension = article.feed?.preferExtensionBrowser ?? settings.defaultOpenInExtensionBrowser
        if useExtension, let url = article.resolvedURL {
            browserTarget = BrowserTarget(url: url, title: article.title, article: article)
        } else {
            readerArticle = article
        }
    }

    private func refresh() async {
        if case .feed(let url) = scope {
            var d = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == url })
            d.fetchLimit = 1
            if let feed = try? modelContext.fetch(d).first { try? await sync.refresh(feed: feed, in: modelContext) }
        } else {
            let feeds = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []
            await sync.refreshAll(feeds: feeds, in: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        ArticleListView(scope: .all, title: "Stream")
    }
    .chromaPreviewEnvironment()
}
