import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FeedSyncService.self) private var sync
    @Environment(AppSettings.self) private var settings

    @State private var urlText = ""
    @State private var folder = ""
    @State private var preferExtension = true
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Feed or website address") {
                    TextField("https://example.com/feed.xml", text: $urlText)
                        .chromaURLField()
                    TextField("Folder (optional)", text: $folder)
                    Toggle("Open articles in extension browser", isOn: $preferExtension)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button {
                        subscribe(urlText)
                    } label: {
                        HStack {
                            Text("Subscribe")
                            if isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                }
                Section("Suggestions") {
                    ForEach(StarterFeedPreset.all) { preset in
                        Button {
                            folder = preset.folder
                            subscribe(preset.url)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(preset.title)
                                Text(preset.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .navigationTitle("Add Feed")
            .chromaInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { preferExtension = settings.defaultOpenInExtensionBrowser }
        }
    }

    private func subscribe(_ input: String) {
        isWorking = true
        errorText = nil
        Task {
            do {
                try await sync.subscribe(urlInput: input, folderName: folder, preferExtensionBrowser: preferExtension, in: modelContext)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }
}
