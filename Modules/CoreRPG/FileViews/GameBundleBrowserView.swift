// @copyright André Trettin

#if !os(tvOS)
    import SwiftUI
    import WebKit

    /// Browses the free game bundle repository inside the app. A tap on a `.gmz` file downloads it
    /// and hands it to `onDownloaded`, which starts the import.
    struct GameBundleBrowserView: View {
        let onDownloaded: @MainActor (URL) -> Void

        @State private var model = GameBundleBrowserModel()
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                WebView(model.page)
                    .webViewBackForwardNavigationGestures(.enabled)
                    .safeAreaInset(edge: .bottom) {
                        GameBundleBrowserStatusView(status: model.status)
                    }
                    .navigationTitle(model.page.title.isEmpty ? "MasterRPG" : model.page.title)
                    .navigationBarTitleDisplayModeAll(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .cancel) {
                                dismiss()
                            } label: {
                                Label {
                                    Text("Close", bundle: .module)
                                } icon: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button {
                                model.goBack()
                            } label: {
                                Label {
                                    Text("Back", bundle: .module)
                                } icon: {
                                    Image(systemName: "chevron.backward")
                                }
                            }
                            .disabled(model.page.backForwardList.backList.isEmpty)
                            Button {
                                model.goForward()
                            } label: {
                                Label {
                                    Text("Forward", bundle: .module)
                                } icon: {
                                    Image(systemName: "chevron.forward")
                                }
                            }
                            .disabled(model.page.backForwardList.forwardList.isEmpty)
                        }
                    }
            }
            .onChange(of: model.page.url) { _, url in
                model.pageUrlChanged(url)
            }
            .onChange(of: model.downloadedFile) { _, fileUrl in
                guard let fileUrl else { return }
                onDownloaded(fileUrl)
                dismiss()
            }
            .onDisappear {
                model.cancelDownload()
            }
        }
    }

    private struct GameBundleBrowserStatusView: View {
        let status: GameBundleBrowserModel.Status

        var body: some View {
            switch status {
            case .idle:
                EmptyView()
            case .downloading(let name):
                HStack {
                    ProgressView()
                    Text("Downloading \(name)", bundle: .module)
                        .lineLimit(1)
                }
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            case .blocked:
                Text("Only the MasterRPG game bundle repository can be opened here.", bundle: .module)
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
    }
#endif
