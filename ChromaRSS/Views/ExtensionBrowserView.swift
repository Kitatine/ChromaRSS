import SwiftUI
import WebKit
import ChromaRSSCore

struct ExtensionBrowserView: View {
    let target: BrowserTarget

    @Environment(ExtensionManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State private var session: BrowserSession?
    @State private var showTabs = false
    @State private var showSummary = false

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                browser(session)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            guard session == nil else { return }
            let s = BrowserSession(manager: manager)
            session = s
            s.start(initialURL: target.url)
        }
        .onDisappear { session?.end() }
        .onChange(of: session?.shouldDismiss ?? false) { _, newValue in if newValue { dismiss() } }
    }

    @ViewBuilder
    private func browser(_ session: BrowserSession) -> some View {
        let tab = session.activeTab
        topBar(session, tab)
        if let tab, tab.isLoading { ProgressView(value: tab.progress).progressViewStyle(.linear) }
        Group {
            if let tab { WebViewContainer(webView: tab.webView) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        bottomBar(session, tab)
    }

    private func topBar(_ session: BrowserSession, _ tab: BrowserTabAdapter?) -> some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)) }
            VStack(alignment: .leading, spacing: 1) {
                Text((tab?.title.isEmpty ?? true) ? target.title : (tab?.title ?? ""))
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: tab?.url?.scheme == "https" ? "lock.fill" : "lock.open").font(.caption2)
                    Text(tab?.url?.host ?? target.url.host ?? "").font(.caption).lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { tab?.stopOrReload() } label: {
                Image(systemName: (tab?.isLoading ?? false) ? "xmark.circle" : "arrow.clockwise")
            }
            Button { showTabs = true } label: {
                Text("\(session.tabs.count)")
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 1.5))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .sheet(isPresented: $showTabs) { tabSwitcher(session) }
    }

    private func bottomBar(_ session: BrowserSession, _ tab: BrowserTabAdapter?) -> some View {
        let _ = manager.revision
        return HStack(spacing: 16) {
            Button { tab?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!(tab?.canGoBack ?? false))
            Button { tab?.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!(tab?.canGoForward ?? false))
            Divider().frame(height: 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(manager.enabledRecords) { record in extensionButton(record, tab) }
                    if manager.enabledRecords.isEmpty {
                        Text("No extensions enabled").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            if let article = target.article {
                Button { article.isStarred.toggle() } label: { Image(systemName: article.isStarred ? "star.fill" : "star") }
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
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .font(.title3)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .sheet(isPresented: $showSummary) { summarySheet }
    }

    private func extensionButton(_ record: InstalledExtensionRecord, _ tab: BrowserTabAdapter?) -> some View {
        let badge = manager.badge(for: record.id, tab: tab)
        return Button {
            manager.performAction(for: record.id, in: tab)
        } label: {
            ZStack(alignment: .topTrailing) {
                if let image = manager.icon(for: record.id) {
                    PlatformSupport.image(from: image).resizable().scaledToFit().frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "puzzlepiece.extension").frame(width: 28, height: 28)
                }
                if !badge.isEmpty {
                    Text(badge).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).background(.red, in: Capsule()).offset(x: 8, y: -6)
                }
            }
        }
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
                            if tab.id == session.activeTabID { Image(systemName: "checkmark") }
                        }
                    }
                }
                .onDelete { offsets in
                    let doomed = offsets.map { session.tabs[$0] }
                    doomed.forEach { session.close($0) }
                }
            }
            .navigationTitle("Tabs")
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
                    }
                    .padding()
                }
            }
            .navigationTitle("Summary")
            .chromaInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSummary = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
