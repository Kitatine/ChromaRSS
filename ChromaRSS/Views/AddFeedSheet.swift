import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    var onSubscribed: ((Feed) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.chromaTheme) private var theme
    @Environment(FeedSyncService.self) private var sync
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Feed.title) private var existingFeeds: [Feed]

    @State private var urlText = ""
    @State private var folder = ""
    @State private var preferExtension = true
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var addedStatusText: String?
    @FocusState private var isURLFocused: Bool

    private var folderSuggestions: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for candidate in ["Tech", "Foreign Language", "News"] + existingFeeds.compactMap({ $0.folderName?.nilIfEmpty }) {
            if seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ChromaSpacing.l) {
                    subscribeCard
                    feedbackBanners
                    starterFeedsCard
                }
                .padding(ChromaSpacing.m)
            }
            .background(theme.canvasColor.ignoresSafeArea())
            .navigationTitle("Add Feed")
            .chromaInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                preferExtension = settings.defaultOpenInExtensionBrowser
                isURLFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 580)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var subscribeCard: some View {
        VStack(alignment: .leading, spacing: ChromaSpacing.m) {
            VStack(alignment: .leading, spacing: ChromaSpacing.xxs) {
                Text("Subscribe by URL or Website")
                    .font(.headline)
                Text("Paste an RSS, Atom, or JSON Feed link—or any website URL and ChromaRSS will auto-discover its feed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: ChromaSpacing.xs) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("Feed or website URL", text: $urlText, prompt: Text("https://zenn.dev, simonwillison.net, or feed.xml"))
                    .textFieldStyle(.plain)
                    .chromaURLField()
                    .focused($isURLFocused)
                    .onSubmit { subscribeCustomURL() }

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear URL")
                }

                Button {
                    if let pasted = PlatformSupport.clipboardString()?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pasted.isEmpty {
                        urlText = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, ChromaSpacing.s)
            .padding(.vertical, 10)
            .background(theme.elevatedColor, in: RoundedRectangle(cornerRadius: ChromaRadius.m))
            .overlay(
                RoundedRectangle(cornerRadius: ChromaRadius.m)
                    .strokeBorder(theme.borderColor, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: ChromaSpacing.xs) {
                HStack(spacing: ChromaSpacing.xs) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    TextField("Folder", text: $folder, prompt: Text("Folder (optional, e.g. Tech, Foreign Language)"))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, ChromaSpacing.s)
                .padding(.vertical, 10)
                .background(theme.elevatedColor, in: RoundedRectangle(cornerRadius: ChromaRadius.m))
                .overlay(
                    RoundedRectangle(cornerRadius: ChromaRadius.m)
                        .strokeBorder(theme.borderColor, lineWidth: 1)
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ChromaSpacing.xs) {
                        ForEach(folderSuggestions, id: \.self) { name in
                            let selected = folder == name
                            Button {
                                folder = selected ? "" : name
                            } label: {
                                Text(name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selected ? ChromaPalette.unreadIndigo : theme.elevatedColor, in: Capsule())
                                    .foregroundStyle(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Toggle("Open articles in Chrome Extension Browser", isOn: $preferExtension)
                .font(.subheadline)

            Button {
                subscribeCustomURL()
            } label: {
                HStack(spacing: ChromaSpacing.xs) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(isWorking ? "Discovering Feed…" : "Subscribe")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
        }
        .padding(ChromaSpacing.m)
        .chromaCardSurface(theme: theme, cornerRadius: ChromaRadius.l)
    }

    @ViewBuilder
    private var feedbackBanners: some View {
        if let errorText {
            HStack(alignment: .top, spacing: ChromaSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ChromaPalette.coral)
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(ChromaSpacing.s)
            .background(ChromaPalette.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: ChromaRadius.m))
            .overlay(
                RoundedRectangle(cornerRadius: ChromaRadius.m)
                    .strokeBorder(ChromaPalette.coral.opacity(0.35), lineWidth: 1)
            )
        }

        if let addedStatusText {
            HStack(spacing: ChromaSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ChromaPalette.emerald)
                Text(addedStatusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(ChromaSpacing.s)
            .background(ChromaPalette.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: ChromaRadius.m))
            .overlay(
                RoundedRectangle(cornerRadius: ChromaRadius.m)
                    .strokeBorder(ChromaPalette.emerald.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var starterFeedsCard: some View {
        VStack(alignment: .leading, spacing: ChromaSpacing.s) {
            HStack {
                Text("Popular & Bilingual Feeds")
                    .font(.headline)
                Spacer()
                Button("Add All") {
                    addAllStarterFeeds()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)
            }

            VStack(spacing: 0) {
                ForEach(Array(StarterFeedPreset.all.enumerated()), id: \.element.id) { index, preset in
                    let isSubscribed = existingFeeds.contains { $0.feedURL == preset.url }
                    HStack(spacing: ChromaSpacing.s) {
                        FeedAvatarView(title: preset.title, siteURL: preset.url, feedURL: preset.url, iconURL: nil, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(preset.folder)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(theme.elevatedColor, in: Capsule())
                                    .foregroundStyle(.secondary)
                                if let host = URL(string: preset.url)?.host {
                                    Text(host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        if isSubscribed {
                            Label("Subscribed", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ChromaPalette.emerald)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ChromaPalette.emerald.opacity(0.12), in: Capsule())
                        } else {
                            Button {
                                subscribePreset(preset)
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isWorking)
                        }
                    }
                    .padding(.vertical, ChromaSpacing.xs)

                    if index < StarterFeedPreset.all.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .padding(ChromaSpacing.m)
        .chromaCardSurface(theme: theme, cornerRadius: ChromaRadius.l)
    }

    private func subscribeCustomURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        errorText = nil
        addedStatusText = nil
        Task {
            do {
                let feed = try await sync.subscribe(
                    urlInput: trimmed,
                    folderName: folder,
                    preferExtensionBrowser: preferExtension,
                    in: modelContext
                )
                onSubscribed?(feed)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func subscribePreset(_ preset: StarterFeedPreset) {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        addedStatusText = nil
        Task {
            do {
                let feed = try await sync.subscribe(
                    urlInput: preset.url,
                    folderName: preset.folder,
                    preferExtensionBrowser: preferExtension,
                    in: modelContext
                )
                onSubscribed?(feed)
                addedStatusText = "Subscribed to \(feed.title)"
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func addAllStarterFeeds() {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        addedStatusText = nil
        Task {
            await sync.addStarterFeeds(preferExtensionBrowser: preferExtension, in: modelContext)
            if let err = sync.lastError {
                errorText = err
            } else {
                addedStatusText = "Added starter feeds"
            }
            isWorking = false
        }
    }
}

#Preview {
    AddFeedSheet()
        .chromaPreviewEnvironment()
}
