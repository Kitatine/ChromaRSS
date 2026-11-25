import SwiftUI
import WebKit

struct ExtensionManagerView: View {
    @Environment(ExtensionManager.self) private var manager
    @State private var showInstall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Immersive Translate", systemImage: "character.bubble").font(.headline)
                        Text("Install the real Chrome extension and use it on any article you open from your feeds.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Install Immersive Translate") { showInstall = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
                Section("Installed") {
                    if manager.records.isEmpty {
                        Text("No extensions installed").foregroundStyle(.secondary)
                    }
                    ForEach(manager.records) { record in ExtensionRow(record: record) }
                        .onDelete { offsets in
                            for i in offsets { try? manager.removeExtension(id: manager.records[i].id) }
                        }
                }
            }
            .navigationTitle("Extensions")
            .toolbar {
                ToolbarItem(placement: .chromaTrailing) {
                    Button("Install Extension", systemImage: "plus") { showInstall = true }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showInstall) { InstallExtensionSheet() }
        }
    }
}

struct ExtensionRow: View {
    let record: InstalledExtensionRecord
    @Environment(ExtensionManager.self) private var manager

    var body: some View {
        let _ = manager.revision
        let ctx = manager.contexts[record.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Group {
                    if let image = manager.icon(for: record.id, size: 40) {
                        PlatformSupport.image(from: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "puzzlepiece.extension").font(.title2)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name).font(.headline)
                    HStack(spacing: 6) {
                        Text("v\(record.version)")
                        Text("MV\(record.manifestVersion)")
                            .padding(.horizontal, 5).background(.quaternary, in: Capsule())
                        if record.isBundled { Text("Built-in") }
                        if record.wasPatchedForiOS { Text("Patched for iOS") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enable \(record.name)", isOn: Binding(
                    get: { record.isEnabled },
                    set: { value in Task { await manager.setEnabled(value, for: record.id) } }))
                    .labelsHidden()
            }
            if !record.descriptionText.isEmpty {
                Text(record.descriptionText).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            if let ctx, ctx.webExtension.hasOptionsPage {
                Button { manager.openOptions(for: record.id) } label: { Label("Options", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.bordered).controlSize(.small)
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
        .padding(.vertical, 4)
    }
}

#Preview {
    ExtensionManagerView()
        .chromaPreviewEnvironment()
}
