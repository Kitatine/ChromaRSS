import SwiftUI
import WebKit
import ChromaRSSCore

struct ExtensionBrowserView: View {
    let target: BrowserTarget
    var isEmbedded: Bool = false

    @Environment(ExtensionManager.self) private var manager
    @Environment(\.chromaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var session: BrowserSession?
    @State private var showTabs = false
    @State private var showSummary = false

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                browser(session)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.canvasColor)
            }
        }
        .onAppear {
            guard session == nil else { return }
            let s = BrowserSession(manager: manager)
            session = s
            s.start(initialURL: target.url)
        }
        .onDisappear { session?.end() }
        .onChange(of: session?.shouldDismiss ?? false) { _, newValue in
            if newValue && !isEmbedded { dismiss() }
        }
    }

    @ViewBuilder
    private func browser(_ session: BrowserSession) -> some View {
        let tab = session.activeTab
        topBar(session, tab)
        Group {
            if let tab { WebViewContainer(webView: tab.webView) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        bottomBar(session, tab)
    }

    private func topBar(_ session: BrowserSession, _ tab: BrowserTabAdapter?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: ChromaSpacing.s) {
                if !isEmbedded {
                    Button("Close Browser", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(theme.elevatedColor, in: Circle())
                        .buttonStyle(.plain)
                }

                // Floating URL / Title capsule
                HStack(spacing: ChromaSpacing.xs) {
                    Image(systemName: tab?.url?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.caption)
                        .foregroundStyle(tab?.url?.scheme == "https" ? ChromaPalette.emerald : .secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text((tab?.title.isEmpty ?? true) ? target.title : (tab?.title ?? ""))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(tab?.url?.host ?? target.url.host ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button((tab?.isLoading ?? false) ? "Stop Loading" : "Reload Page",
                           systemImage: (tab?.isLoading ?? false) ? "xmark" : "arrow.clockwise") {
                        tab?.stopOrReload()
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.elevatedColor, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.borderColor, lineWidth: 1))

                Button { showTabs = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.on.square")
                            .font(.caption)
                        Text("\(session.tabs.count)")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(theme.elevatedColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Tabs, \(session.tabs.count)")
            }
            .padding(.horizontal, ChromaSpacing.m)
            .padding(.vertical, ChromaSpacing.xs)

            if let tab, tab.isLoading {
                ProgressView(value: tab.progress)
                    .progressViewStyle(.linear)
                    .tint(ChromaPalette.unreadIndigo)
            }
        }
        .background(theme.surfaceColor)
        .sheet(isPresented: $showTabs) { tabSwitcher(session) }
    }

    private func bottomBar(_ session: BrowserSession, _ tab: BrowserTabAdapter?) -> some View {
        let _ = manager.revision
        return HStack(spacing: ChromaSpacing.s) {
            HStack(spacing: 14) {
                Button("Back", systemImage: "chevron.left") { tab?.goBack() }
                    .labelStyle(.iconOnly)
                    .disabled(!(tab?.canGoBack ?? false))
                Button("Forward", systemImage: "chevron.right") { tab?.goForward() }
                    .labelStyle(.iconOnly)
                    .disabled(!(tab?.canGoForward ?? false))
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.plain)

            // Chrome Extension Strip inside a prominent pill
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ChromaSpacing.s) {
                    ForEach(manager.enabledRecords) { record in
                        extensionButton(record, tab)
                    }
                    if manager.enabledRecords.isEmpty {
                        Label("No Plugins", systemImage: "puzzlepiece.extension")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(height: 34)
            .background(ChromaPalette.unreadIndigo.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(ChromaPalette.unreadIndigo.opacity(0.24), lineWidth: 1))

            if let article = target.article {
                Button(article.isStarred ? "Remove Bookmark" : "Bookmark Article",
                       systemImage: article.isStarred ? "bookmark.fill" : "bookmark") {
                    article.isStarred.toggle()
                }
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(article.isStarred ? ChromaPalette.starAmber : .primary)
                .buttonStyle(.plain)
            }

            Menu {
                if let url = tab?.url ?? Optional(target.url) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { PlatformSupport.openExternalURL(url) } label: { Label("Open in Safari", systemImage: "safari") }
                    Button {
                        let chrome = url.absoluteString
                            .replacingOccurrences(of: "https://", with: "googlechromes://")
                            .replacingOccurrences(of: "http://", with: "googlechrome://")
                        if let u = URL(string: chrome) { PlatformSupport.openExternalURL(u) }
                    } label: { Label("Open in Chrome App", systemImage: "globe") }
                }
                if target.article != nil {
                    Button { showSummary = true } label: { Label("Article Summary", systemImage: "text.alignleft") }
                }
            } label: {
                Label("Browser Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, ChromaSpacing.m)
        .padding(.vertical, ChromaSpacing.xs)
        .background(theme.surfaceColor)
        .sheet(isPresented: $showSummary) { summarySheet }
    }

    private func extensionButton(_ record: InstalledExtensionRecord, _ tab: BrowserTabAdapter?) -> some View {
        let badge = manager.badge(for: record.id, tab: tab)
        return Button {
            manager.performAction(for: record.id, in: tab)
        } label: {
            HStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    if let image = manager.icon(for: record.id) {
                        PlatformSupport.image(from: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.subheadline)
                            .foregroundStyle(ChromaPalette.unreadIndigo)
                            .frame(width: 22, height: 22)
                    }
                    if !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(ChromaPalette.coral, in: Capsule())
                            .offset(x: 6, y: -5)
                    }
                }
                Text(record.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.isEmpty ? record.name : "\(record.name), \(badge)")
        .contextMenu {
            Text(record.name)
            Button { manager.openOptions(for: record.id) } label: { Label("Extension Options", systemImage: "slider.horizontal.3") }
            Button { Task { await manager.reload(id: record.id) } } label: { Label("Reload Extension", systemImage: "arrow.clockwise") }
        }
    }

    private func tabSwitcher(_ session: BrowserSession) -> some View {
        NavigationStack {
            List {
                ForEach(session.tabs) { tab in
                    Button {
                        session.select(tab)
                        showTabs = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title).lineLimit(1)
                                Text(tab.url?.absoluteString ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if tab.id == session.activeTabID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ChromaPalette.unreadIndigo)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let doomed = offsets.map { session.tabs[$0] }
                    doomed.forEach { session.close($0) }
                }
            }
            .navigationTitle("Open Tabs")
            .chromaInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTabs = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var summarySheet: some View {
        NavigationStack {
            ScrollView {
                if let article = target.article {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(article.title).font(.title3.bold())
                        Text(HTMLTextExtractor.plainText(from: article.summary ?? article.contentHTML ?? "", maxLength: 0, preserveParagraphs: true))
                            .lineSpacing(5)
                    }
                    .padding()
                }
            }
            .navigationTitle("Article Summary")
            .chromaInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSummary = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
