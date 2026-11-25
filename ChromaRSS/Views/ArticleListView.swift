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
        case all, unread, starred
        case feed(String)
    }
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unread = "Unread", starred = "Starred"
        var id: String { rawValue }
    }

    let scope: Scope
    let title: String

    @Environment(\.modelContext) private var modelContext
    @Environment(FeedSyncService.self) private var sync
    @Environment(AppSettings.self) private var settings
    @Query private var articles: [Article]

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var browserTarget: BrowserTarget?
    @State private var readerArticle: Article?

    init(scope: Scope, title: String) {
        self.scope = scope
        self.title = title
        let sort = [SortDescriptor(\Article.sortDate, order: .reverse)]
        switch scope {
        case .all:
            _articles = Query(sort: sort)
        case .unread:
            _articles = Query(filter: #Predicate<Article> { !$0.isRead }, sort: sort)
        case .starred:
            _articles = Query(filter: #Predicate<Article> { $0.isStarred }, sort: sort)
        case .feed(let url):
            _articles = Query(filter: #Predicate<Article> { $0.feedURL == url }, sort: sort)
        }
    }

    private var visible: [Article] {
        articles.filter { a in
            switch filter {
            case .all: true
            case .unread: !a.isRead
            case .starred: a.isStarred
            }
        }
        .filter { search.isEmpty || $0.title.localizedStandardContains(search) || ($0.summary ?? "").localizedStandardContains(search) }
    }

    var body: some View {
        List(visible) { article in
            Button { open(article) } label: { ArticleRow(article: article) }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button { article.isStarred.toggle() } label: { Label("Star", systemImage: article.isStarred ? "star.slash" : "star") }
                        .tint(.yellow)
                }
                .swipeActions(edge: .trailing) {
                    Button { article.isRead.toggle() } label: {
                        Label(article.isRead ? "Unread" : "Read", systemImage: article.isRead ? "circle" : "checkmark")
                    }
                    .tint(.blue)
                }
        }
        .listStyle(.plain)
        .overlay {
            if visible.isEmpty { ContentUnavailableView("No Articles", systemImage: "tray", description: Text("Pull down to refresh.")) }
        }
        .navigationTitle(title)
        .chromaInlineTitle()
        .searchable(text: $search)
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .chromaTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button { for a in articles { a.isRead = true } } label: { Label("Mark All as Read", systemImage: "checkmark.circle") }
                } label: {
                    Label("Filter Articles", systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .chromaBrowserPresentation(item: $browserTarget) { ExtensionBrowserView(target: $0) }
        .navigationDestination(item: $readerArticle) { ArticleReaderView(article: $0) }
    }

    private func open(_ article: Article) {
        article.isRead = true
        let useExtension = article.feed?.preferExtensionBrowser ?? settings.defaultOpenInExtensionBrowser
        if useExtension, let url = URL(string: article.link) {
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

struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !article.isRead {
                        Circle().fill(.blue).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                    Text(article.title)
                        .font(.headline.weight(article.isRead ? .regular : .semibold))
                        .foregroundStyle(article.isRead ? .secondary : .primary)
                        .lineLimit(3)
                }
                if let snippet = snippet, !snippet.isEmpty {
                    Text(snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let name = article.feed?.title { Text(name).lineLimit(1) }
                    if let date = article.publishedAt { Text("·"); Text(date, style: .relative) }
                    if article.isStarred {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                    }
                }
                .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let img = article.imageURL, let url = URL(string: img) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.gray.opacity(0.15) }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .contentShape(Rectangle())
    }

    private var snippet: String? {
        guard let s = article.summary ?? article.contentHTML else { return nil }
        return HTMLTextExtractor.plainText(from: s, maxLength: 200)
    }
}

#Preview {
    NavigationStack {
        ArticleListView(scope: .all, title: "All Articles")
    }
    .chromaPreviewEnvironment()
}
