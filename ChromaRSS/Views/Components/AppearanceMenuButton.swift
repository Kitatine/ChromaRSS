import SwiftUI

struct AppearanceMenuButton: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        Menu {
            Picker("Layout", selection: $s.streamLayout) {
                ForEach(StreamLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            Picker("Typography", selection: $s.headlineDesign) {
                ForEach(HeadlineDesign.allCases) { design in
                    Text(design.title).tag(design)
                }
            }
            Picker("Theme", selection: $s.readerTheme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Label(theme.title, systemImage: theme.systemImage).tag(theme)
                }
            }
        } label: {
            Label("Appearance", systemImage: "eye")
                .labelStyle(.iconOnly)
        }
    }
}

enum StreamFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case saved = "Saved"
    case today = "Today"

    var id: String { rawValue }
}

struct FilterPillBar: View {
    @Binding var selection: StreamFilter
    let unreadCount: Int
    @Environment(\.chromaTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ChromaSpacing.xs) {
                ForEach(StreamFilter.allCases) { item in
                    let isSelected = selection == item
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selection = item
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.rawValue)
                            if item == .unread && unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(isSelected ? Color.white.opacity(0.24) : ChromaPalette.unreadIndigo.opacity(0.14),
                                                in: Capsule())
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(isSelected ? AnyShapeStyle(ChromaPalette.unreadIndigo) : AnyShapeStyle(theme.surfaceColor),
                                    in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? Color.clear : theme.borderColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ChromaSpacing.m)
            .padding(.vertical, ChromaSpacing.xs)
        }
    }
}
