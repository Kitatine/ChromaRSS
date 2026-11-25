import SwiftUI
import UniformTypeIdentifiers

struct InstallExtensionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ExtensionManager.self) private var manager

    @State private var input = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var successText: String?
    @State private var importing = false

    private let immersiveID = "bpoadfkcbjbfhfodiogcnhhhpibjhbnh"
    private let releasesURL = URL(string: "https://github.com/immersive-translate/immersive-translate/releases")!

    var body: some View {
        NavigationStack {
            Form {
                Section("Immersive Translate Quick Install") {
                    Button { run { try await manager.installFromRemoteInput(immersiveID) } } label: {
                        Label("Fetch from Chrome Web Store", systemImage: "arrow.down.circle")
                    }
                    Link(destination: releasesURL) {
                        Label("Download the .zip from GitHub Releases", systemImage: "safari")
                    }
                    Button { importing = true } label: { Label("Import .zip / .crx from Files…", systemImage: "folder") }
                }
                Section {
                    TextField("Chrome Web Store URL, extension ID or .crx/.zip URL", text: $input, axis: .vertical)
                        .chromaURLField()
                    Button("Install") { run { try await manager.installFromRemoteInput(input) } }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Any Chrome extension")
                } footer: {
                    Text("Works with Manifest V2 and V3 packages. Extensions that need Chrome-only APIs may only partly work in WebKit.")
                }
                if isWorking { Section { HStack { ProgressView(); Text("Installing…") } } }
                if let errorText { Section { Text(errorText).foregroundStyle(.red).font(.footnote) } }
                if let successText { Section { Label(successText, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            }
            .disabled(isWorking)
            .navigationTitle("Install Extension")
            .chromaInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .data, .item]) { result in
                switch result {
                case .success(let url): run { try await manager.installFromFile(url: url) }
                case .failure(let error): errorText = error.localizedDescription
                }
            }
        }
    }

    private func run(_ operation: @escaping () async throws -> InstalledExtensionRecord) {
        isWorking = true
        errorText = nil
        successText = nil
        Task {
            do {
                let record = try await operation()
                successText = "Installed \(record.name) \(record.version)"
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview {
    InstallExtensionSheet()
        .chromaPreviewEnvironment()
}
