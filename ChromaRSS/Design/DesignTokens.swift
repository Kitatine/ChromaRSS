import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ChromaSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 28
}

enum ChromaRadius {
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 22
    static let pill: CGFloat = 999
}

enum StreamLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case magazine
    case cards
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magazine: "Magazine"
        case .cards: "Cards"
        case .compact: "Compact"
        }
    }

    var systemImage: String {
        switch self {
        case .magazine: "rectangle.grid.1x2"
        case .cards: "square.text.square"
        case .compact: "list.bullet"
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case sepia
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Paper"
        case .sepia: "Sepia"
        case .dark: "Midnight"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .sepia: "book.pages"
        case .dark: "moon.stars"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .sepia: .light
        case .dark: .dark
        }
    }

    var canvasColor: Color {
        switch self {
        case .system: ChromaPalette.systemCanvas
        case .light: Color(red: 0.953, green: 0.961, blue: 0.976)
        case .sepia: Color(red: 0.961, green: 0.937, blue: 0.894)
        case .dark: Color(red: 0.059, green: 0.067, blue: 0.090)
        }
    }

    var surfaceColor: Color {
        switch self {
        case .system: ChromaPalette.systemSurface
        case .light: .white
        case .sepia: Color(red: 0.984, green: 0.969, blue: 0.937)
        case .dark: Color(red: 0.098, green: 0.114, blue: 0.149)
        }
    }

    var elevatedColor: Color {
        switch self {
        case .system: ChromaPalette.systemElevated
        case .light: Color(red: 0.918, green: 0.929, blue: 0.953)
        case .sepia: Color(red: 0.929, green: 0.898, blue: 0.835)
        case .dark: Color(red: 0.137, green: 0.157, blue: 0.204)
        }
    }

    var borderColor: Color {
        switch self {
        case .system: Color.primary.opacity(0.08)
        case .light: Color.black.opacity(0.07)
        case .sepia: Color(red: 0.45, green: 0.36, blue: 0.24).opacity(0.16)
        case .dark: Color.white.opacity(0.09)
        }
    }
}

enum HeadlineDesign: String, CaseIterable, Identifiable, Sendable {
    case serif
    case sans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serif: "Editorial Serif"
        case .sans: "Modern Sans"
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        }
    }
}

enum ChromaPalette {
    static let unreadIndigo = Color(red: 0.231, green: 0.357, blue: 0.859)
    static let starAmber = Color(red: 0.945, green: 0.616, blue: 0.118)
    static let emerald = Color(red: 0.118, green: 0.635, blue: 0.435)
    static let coral = Color(red: 0.902, green: 0.322, blue: 0.298)
    static let teal = Color(red: 0.078, green: 0.569, blue: 0.663)
    static let plum = Color(red: 0.506, green: 0.294, blue: 0.788)

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.176, green: 0.259, blue: 0.722),
            Color(red: 0.275, green: 0.435, blue: 0.918)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let monogramPairs: [(Color, Color)] = [
        (Color(red: 0.23, green: 0.36, blue: 0.86), Color(red: 0.36, green: 0.51, blue: 0.96)),
        (Color(red: 0.08, green: 0.57, blue: 0.66), Color(red: 0.15, green: 0.72, blue: 0.76)),
        (Color(red: 0.85, green: 0.33, blue: 0.27), Color(red: 0.95, green: 0.49, blue: 0.34)),
        (Color(red: 0.48, green: 0.28, blue: 0.77), Color(red: 0.65, green: 0.42, blue: 0.91)),
        (Color(red: 0.13, green: 0.61, blue: 0.43), Color(red: 0.22, green: 0.76, blue: 0.56)),
        (Color(red: 0.82, green: 0.52, blue: 0.12), Color(red: 0.95, green: 0.68, blue: 0.24))
    ]

    static func gradientColors(for seed: String) -> (Color, Color) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return monogramPairs[Int(hash % UInt64(monogramPairs.count))]
    }

    static var systemCanvas: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    static var systemSurface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var systemElevated: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

extension EnvironmentValues {
    @Entry var chromaTheme: ReaderTheme = .system
    @Entry var chromaHeadlineDesign: HeadlineDesign = .serif
}

extension View {
    func chromaCardSurface(theme: ReaderTheme, cornerRadius: CGFloat = ChromaRadius.l) -> some View {
        background(theme.surfaceColor, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(theme.borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(theme == .dark ? 0.25 : 0.045), radius: 8, y: 3)
    }
}
