import SwiftUI
import WebKit

struct ExtensionManagerView: View {
    @Environment(ExtensionManager.self) private var manager
    @Environment(\.chromaTheme) private var theme
    @State private var showInstall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ChromaSpacing.l) {
                    heroBanner

                    VStack(alignment: .leading, spacing: ChromaSpacing.s) {
                        HStack {
                            Text("Installed Plugins")
                                .font(.title3.bold())
                            Spacer()
                            Text("\(manager.enabledRecords.count) active")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ChromaPalette.unreadIndigo)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(ChromaPalette.unreadIndigo.opacity(0.14), in: Capsule())
                        }

                        if manager.records.isEmpty {
                            ContentUnavailableView(
                                "No Extensions Installed",
                                systemImage: "puzzlepiece.extension",
                                description: Text("Install a Chrome .crx or .zip extension to run it inside ChromaRSS.")
                            )
                            .chromaCardSurface(theme: theme)
                        } else {
                            ForEach(manager.records) { record in
                                ExtensionCardRow(record: record)
                            }
                        }
                    }
                }
                .padding(ChromaSpacing.m)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(theme.canvasColor.ignoresSafeArea())
            .navigationTitle("Chrome Plugins")
            .toolbar {
                ToolbarItem(placement: .chromaTrailing) {
                    Button("Install Extension", systemImage: "plus") { showInstall = true }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showInstall) { InstallExtensionSheet() }
        }
    }

    private var heroBanner: some View {
        VStack(alignment: .leading, spacing: ChromaSpacing.s) {
            HStack(spacing: ChromaSpacing.s) {
                Image(systemName: "character.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(ChromaPalette.unreadIndigo)
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: ChromaRadius.m))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Immersive Translate & Chrome Plugins")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Manifest V2 / V3 · Persistent Storage")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer(minLength: 0)
            }

            Text("Install desktop Chrome .crx or .zip extensions directly inside ChromaRSS so every article opens with your translation overlays, popups, and custom settings.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))

            Button {
                showInstall = true
            } label: {
                Label("Install Immersive Translate or Custom .crx / .zip", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChromaPalette.unreadIndigo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.white, in: RoundedRectangle(cornerRadius: ChromaRadius.m))
            }
            .buttonStyle(.plain)
        }
        .padding(ChromaSpacing.l)
        .background(ChromaPalette.heroGradient, in: RoundedRectangle(cornerRadius: ChromaRadius.xl))
        .shadow(color: ChromaPalette.unreadIndigo.opacity(0.28), radius: 14, y: 6)
    }
}

struct ExtensionCardRow: View {
    let record: InstalledExtensionRecord
    @Environment(ExtensionManager.self) private var manager
    @Environment(\.chromaTheme) private var theme

    var body: some View {
        let _ = manager.revision
        let ctx = manager.contexts[record.id]
        VStack(alignment: .leading, spacing: ChromaSpacing.s) {
            HStack(spacing: ChromaSpacing.s) {
                Group {
                    if let image = manager.icon(for: record.id, size: 44) {
                        PlatformSupport.image(from: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.title3)
                            .foregroundStyle(ChromaPalette.unreadIndigo)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(ChromaPalette.unreadIndigo.opacity(0.12))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: ChromaRadius.m))

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text("v\(record.version)")
                        pill("MV\(record.manifestVersion)", tint: .secondary)
                        if record.isBundled { pill("Built-in", tint: ChromaPalette.emerald) }
                        if record.wasPatchedForiOS { pill("iOS Patched", tint: ChromaPalette.starAmber) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Enable \(record.name)", isOn: Binding(
                    get: { record.isEnabled },
                    set: { value in Task { await manager.setEnabled(value, for: record.id) } }
                ))
                .labelsHidden()
            }

            if !record.descriptionText.isEmpty {
                Text(record.descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: ChromaSpacing.xs) {
                if let ctx, ctx.webExtension.hasOptionsPage {
                    Button { manager.openOptions(for: record.id) } label: {
                        Label("Options", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button { Task { await manager.reload(id: record.id) } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if !record.isBundled {
                    Button(role: .destructive) {
                        try? manager.removeExtension(id: record.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            let problems = Array(Set((ctx?.errors.map(\.localizedDescription) ?? []) + [manager.loadErrors[record.id]].compactMap { $0 })).sorted()
            if !problems.isEmpty {
                DisclosureGroup("Diagnostics (\(problems.count))") {
                    ForEach(problems, id: \.self) { text in
                        Text(text).font(.caption).foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
            }
        }
        .padding(ChromaSpacing.m)
        .chromaCardSurface(theme: theme, cornerRadius: ChromaRadius.l)
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    ExtensionManagerView()
        .chromaPreviewEnvironment()
}
