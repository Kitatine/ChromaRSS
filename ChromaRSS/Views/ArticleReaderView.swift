import SwiftUI
import ChromaRSSCore

struct ArticleReaderView: View {
    let article: Article
    @State private var browserTarget: BrowserTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title).font(.title.bold())
                HStack(spacing: 6) {
                    if let author = article.author { Text(author) }
                    if let feed = article.feed?.title { Text(feed) }
                    if let date = article.publishedAt { Text(date, style: .date) }
                }
                .font(.subheadline).foregroundStyle(.secondary)

                if let img = article.imageURL, let url = URL(string: img) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { EmptyView() }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text(bodyText).font(.body).lineSpacing(5)

                if let url = URL(string: article.link) {
                    Button {
                        browserTarget = BrowserTarget(url: url, title: article.title, article: article)
                    } label: {
                        Label("Open in Chrome-Extension Browser", systemImage: "puzzlepiece.extension")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        .chromaInlineTitle()
        .toolbar {
            ToolbarItemGroup(placement: .chromaTrailing) {
                Button { article.isStarred.toggle() } label: { Image(systemName: article.isStarred ? "star.fill" : "star") }
                if let url = URL(string: article.link) { ShareLink(item: url) }
            }
        }
        .chromaBrowserPresentation(item: $browserTarget) { ExtensionBrowserView(target: $0) }
    }

    private var bodyText: String {
        let html = article.contentHTML ?? article.summary ?? ""
        let text = HTMLTextExtractor.plainText(from: html, maxLength: 0, preserveParagraphs: true)
        return text.isEmpty ? "No preview is available for this article. Open it in the browser to read it." : text
    }
}
