import SwiftUI
import ChromaRSSCore

struct SmartStreamTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let count: Int
    @Environment(\.chromaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ChromaSpacing.s) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(ChromaSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chromaCardSurface(theme: theme, cornerRadius: ChromaRadius.l)
    }
}

struct MagazineArticleRow: View {
    let article: Article
    var isSelected: Bool = false

    @Environment(\.chromaTheme) private var theme
    @Environment(\.chromaHeadlineDesign) private var headlineDesign

    var body: some View {
        VStack(alignment: .leading, spacing: ChromaSpacing.xs) {
            ArticleSourceLine(article: article)

            HStack(alignment: .top, spacing: ChromaSpacing.s) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.headline)
                        .fontDesign(headlineDesign.fontDesign)
                        .foregroundStyle(article.isRead ? .secondary : .primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    if let excerpt = articleExcerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let imageURL = article.imageURL, let url = URL(string: imageURL) {
                    ArticleThumbnail(url: url, seed: article.feedURL, width: 82, height: 82)
                }
            }
        }
        .padding(ChromaSpacing.m)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: ChromaRadius.l))
        .overlay(
            RoundedRectangle(cornerRadius: ChromaRadius.l)
                .strokeBorder(isSelected ? ChromaPalette.unreadIndigo.opacity(0.65) : theme.borderColor,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(theme == .dark ? 0.22 : 0.04), radius: 6, y: 2)
    }

    private var cardBackground: Color {
        isSelected ? ChromaPalette.unreadIndigo.opacity(0.08) : theme.surfaceColor
    }

    private var articleExcerpt: String? {
        guard let raw = article.summary ?? article.contentHTML else { return nil }
        return HTMLTextExtractor.plainText(from: raw, maxLength: 180)
    }
}

struct HeroCardArticleView: View {
    let article: Article
    var isSelected: Bool = false
    let onToggleRead: () -> Void
    let onToggleStar: () -> Void

    @Environment(\.chromaTheme) private var theme
    @Environment(\.chromaHeadlineDesign) private var headlineDesign

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroBanner
            VStack(alignment: .leading, spacing: ChromaSpacing.xs) {
                ArticleSourceLine(article: article)

                Text(article.title)
                    .font(.title3.bold())
                    .fontDesign(headlineDesign.fontDesign)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if let excerpt = articleExcerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Divider()
                    .padding(.top, ChromaSpacing.xxs)

                HStack(spacing: ChromaSpacing.m) {
                    Button(article.isStarred ? "Saved" : "Save",
                           systemImage: article.isStarred ? "bookmark.fill" : "bookmark",
                           action: onToggleStar)
                        .foregroundStyle(article.isStarred ? ChromaPalette.starAmber : .secondary)
                    Button(article.isRead ? "Mark Unread" : "Mark Read",
                           systemImage: article.isRead ? "circle" : "checkmark.circle",
                           action: onToggleRead)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("Open + Plugins", systemImage: "puzzlepiece.extension")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ChromaPalette.unreadIndigo)
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .padding(.top, ChromaSpacing.xxs)
            }
            .padding(ChromaSpacing.m)
        }
        .background(isSelected ? ChromaPalette.unreadIndigo.opacity(0.08) : theme.surfaceColor,
                    in: RoundedRectangle(cornerRadius: ChromaRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: ChromaRadius.xl)
                .strokeBorder(isSelected ? ChromaPalette.unreadIndigo.opacity(0.65) : theme.borderColor,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(theme == .dark ? 0.28 : 0.055), radius: 10, y: 4)
    }

    @ViewBuilder
    private var heroBanner: some View {
        if let imageURL = article.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    gradientPlaceholder
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: ChromaRadius.xl, topTrailingRadius: ChromaRadius.xl))
        } else {
            let pair = ChromaPalette.gradientColors(for: article.feedURL)
            LinearGradient(colors: [pair.0.opacity(0.85), pair.1.opacity(0.65)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: ChromaRadius.xl, topTrailingRadius: ChromaRadius.xl))
        }
    }

    private var gradientPlaceholder: some View {
        let pair = ChromaPalette.gradientColors(for: article.feedURL)
        return LinearGradient(colors: [pair.0.opacity(0.25), pair.1.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var articleExcerpt: String? {
        guard let raw = article.summary ?? article.contentHTML else { return nil }
        return HTMLTextExtractor.plainText(from: raw, maxLength: 240)
    }
}

struct CompactArticleRow: View {
    let article: Article
    var isSelected: Bool = false

    @Environment(\.chromaTheme) private var theme
    @Environment(\.chromaHeadlineDesign) private var headlineDesign

    var body: some View {
        HStack(spacing: ChromaSpacing.s) {
            Circle()
                .fill(article.isRead ? Color.clear : ChromaPalette.unreadIndigo)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            FeedAvatarView(
                title: article.feed?.title ?? article.title,
                siteURL: article.feed?.siteURL,
                feedURL: article.feedURL,
                iconURL: article.feed?.iconURL,
                size: 20
            )

            Text(article.title)
                .font(.subheadline.weight(article.isRead ? .regular : .semibold))
                .fontDesign(headlineDesign.fontDesign)
                .foregroundStyle(article.isRead ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: ChromaSpacing.xs)

            if article.isStarred {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(ChromaPalette.starAmber)
                    .accessibilityHidden(true)
            }

            if let date = article.publishedAt {
                Text(date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, ChromaSpacing.m)
        .padding(.vertical, ChromaSpacing.s)
        .background(isSelected ? ChromaPalette.unreadIndigo.opacity(0.08) : theme.surfaceColor,
                    in: RoundedRectangle(cornerRadius: ChromaRadius.m))
        .overlay(
            RoundedRectangle(cornerRadius: ChromaRadius.m)
                .strokeBorder(isSelected ? ChromaPalette.unreadIndigo.opacity(0.6) : theme.borderColor, lineWidth: 1)
        )
    }
}

private struct ArticleSourceLine: View {
    let article: Article

    var body: some View {
        HStack(spacing: 6) {
            if !article.isRead {
                Circle()
                    .fill(ChromaPalette.unreadIndigo)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            FeedAvatarView(
                title: article.feed?.title ?? article.title,
                siteURL: article.feed?.siteURL,
                feedURL: article.feedURL,
                iconURL: article.feed?.iconURL,
                size: 18
            )
            Text(article.feed?.title ?? "Subscription")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let folder = article.feed?.folderName, !folder.isEmpty {
                Text(folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if article.isStarred {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(ChromaPalette.starAmber)
                    .accessibilityHidden(true)
            }
            if let date = article.publishedAt {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ArticleThumbnail: View {
    let url: URL
    let seed: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let pair = ChromaPalette.gradientColors(for: seed)
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                LinearGradient(colors: [pair.0.opacity(0.22), pair.1.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ChromaRadius.m))
        .accessibilityHidden(true)
    }
}
