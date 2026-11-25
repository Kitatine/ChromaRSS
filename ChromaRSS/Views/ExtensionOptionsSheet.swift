import SwiftUI
import WebKit

struct ExtensionOptionsSheet: View {
    let extensionContext: WKWebExtensionContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExtensionPageWebView(extensionContext: extensionContext)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(extensionContext.webExtension.displayName ?? "Options")
                .chromaInlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
