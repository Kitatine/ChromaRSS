import SwiftUI
import ChromaRSSCore

struct ArticleReaderView: View {
    let article: Article
    var showLaunchBrowserButton: Bool = true
    @Environment(\.chromaTheme) private var theme
    @Environment(\.chromaHeadlineDesign) private var headlineDesign
    @State private var browserTarget: BrowserTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChromaSpacing.m) {
                HStack(spacing: ChromaSpacing.s) {
                    FeedAvatarView(
                        title: article.feed?.title ?? article.title,
                        siteURL: article.feed?.siteURL,
                        feedURL: article.feedURL,
                        iconURL: article.feed?.iconURL,
                        size: 30
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(article.feed?.title ?? "Article")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 6) {
                            if let author = article.author { Text(author) }
                            if let date = article.publishedAt { Text(date, style: .date) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(article.title)
                    .font(.title.bold())
                    .fontDesign(headlineDesign.fontDesign)

                if let img = article.imageURL, let url = URL(string: img) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ChromaRadius.l))
                }

                Divider()

                Text(bodyText)
                    .font(.body)
                    .fontDesign(headlineDesign.fontDesign)
                    .lineSpacing(7)

                if showLaunchBrowserButton, let url = article.resolvedURL {
                    Button {
                        browserTarget = BrowserTarget(url: url, title: article.title, article: article)
                    } label: {
                        Label("Launch in Chrome-Extension Browser", systemImage: "puzzlepiece.extension.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(ChromaPalette.heroGradient, in: RoundedRectangle(cornerRadius: ChromaRadius.m))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, ChromaSpacing.s)
                }
            }
            .padding(ChromaSpacing.l)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.surfaceColor.ignoresSafeArea())
        .chromaInlineTitle()
        .toolbar {
            ToolbarItemGroup(placement: .chromaTrailing) {
                Button(article.isStarred ? "Remove Bookmark" : "Bookmark Article",
                       systemImage: article.isStarred ? "bookmark.fill" : "bookmark") {
                    article.isStarred.toggle()
                }
                .labelStyle(.iconOnly)
                if let url = article.resolvedURL { ShareLink(item: url) }
            }
        }
        .chromaBrowserPresentation(item: $browserTarget) { ExtensionBrowserView(target: $0) }
    }

    private var bodyText: String {
        let html = article.contentHTML ?? article.summary ?? ""
        let text = HTMLTextExtractor.plainText(from: html, maxLength: 0, preserveParagraphs: true)
        return text.isEmpty ? "No summary preview was included in this feed item. Launch the full page in the Chrome-Extension Browser to read and translate it." : text
    }
}

#Preview {
    let container = PreviewSampleData.makeContainer()
    NavigationStack {
        ArticleReaderView(article: PreviewSampleData.sampleArticle(in: container))
    }
    .chromaPreviewEnvironment(container: container)
}
