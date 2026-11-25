import SwiftUI

struct FeedAvatarView: View {
    let title: String
    let siteURL: String?
    let feedURL: String
    var iconURL: String?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = resolvedIconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .background(.white)
                    default:
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        let pair = ChromaPalette.gradientColors(for: feedURL)
        return ZStack {
            LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initial)
                .font(.system(size: max(10, size * 0.5), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initial: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "R" }
        return String(first).uppercased()
    }

    private var resolvedIconURL: URL? {
        if let iconURL, let url = URL(string: iconURL), url.scheme?.hasPrefix("http") == true {
            return url
        }
        let candidate = siteURL ?? feedURL
        guard let host = URL(string: candidate)?.host,
              host != "127.0.0.1",
              host != "localhost" else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }
}
