// @copyright André Trettin

import SwiftUI

public protocol ExampleUrlProvider {
    @MainActor func urlExampleData(isGerman: Bool) -> URL?
}

public struct ImportProgressPanelView: View {
    public init(importController: any ImportControllable) {
        self.urlProvider = nil
        self.importController = importController
        self.isSaveGame = true
    }

    public init(urlProvider: any ExampleUrlProvider, importController: any ImportControllable) {
        self.urlProvider = urlProvider
        self.importController = importController
        self.isSaveGame = false
    }

    let urlProvider: (any ExampleUrlProvider)?
    let importController: any ImportControllable
    let isSaveGame: Bool

    @Environment(\.navigator) private var navigator

    @State private var importModel = ItemDataImportModel()
    @State private var showImportFileChooser = false
    @State private var outcome: ImportOutcome = .notStarted

    @State private var loadUrl: URL?
    @State private var importTask: Task<Void, any Error>?

    public var body: some View {
        NavigationStack {
            Group {
                if importModel.isReviewReady {
                    reviewContent
                } else {
                    VStack {
                        progressView
                        statusText
                    }
                    .padding()
                }
            }
            .navigationTitle(Text("Importing", bundle: .module))
            .navigationBarTitleDisplayModeAll(.inline)
            .task(id: loadUrl) {
                guard let loadUrl else { return }
                do {
                    outcome = .running
                    importTask = importController.importUrl(from: loadUrl, importModel: importModel)
                    try await importTask?.value
                    outcome = .finished
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    outcome = .failed(error.localizedDescription)
                }
            }

#if !os(tvOS)
            .fileImporter(isPresented: $showImportFileChooser, allowedContentTypes: [isSaveGame ? .gmsDocument : .rpgDocument]) { result in
                do {
                    loadUrl = try result.get()
                    outcome = .running
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    outcome = .failed(error.localizedDescription)
                }
            }
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        importTask?.cancel()
                        navigator.dismiss()
                    } label: {
                        Label { Text("Cancel", bundle: .module) } icon: { Image(systemName: "xmark") }
                    }
                }

                if !importModel.isReviewReady {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            navigator.dismiss()
                        } label: {
                            Label { Text("Ok", bundle: .module) } icon: { Image(systemName: "checkmark") }
                        }
                        .disabled(importModel.isImportRunning)
                    }
                }
            }
        }
    }

    private enum ImportOutcome {
        case notStarted
        case running
        case cancelled
        case finished
        case failed(String)
    }
}

private extension ImportProgressPanelView {
    @ViewBuilder var reviewContent: some View {
        @Bindable var bm = importModel
        ImportReviewView(reviewItems: $bm.reviewItems) {
            let items = importModel.reviewItems
            for item in items {
                await item.applyResolution(item.resolution)
            }
            importModel.isReviewReady = false
            importModel.reviewItems = []
            navigator.dismiss()
        }
    }

    @ViewBuilder var progressView: some View {
        if importModel.isImportRunning && importModel.totalImportingItems > 0 {
            ProgressView(
                value: Double(importModel.importedItems),
                total: Double(importModel.totalImportingItems)
            )
            .tint(Color.accentColor)
            .accessibilityLabel(Text("Import progress", bundle: .module))
        }
    }

    var chooseUrlButtons: some View {
        VStack(spacing: 20) {
            Button {
                showImportFileChooser = true
            } label: {
                Label {
                    Text("Choose file", bundle: .module)
                } icon: {
                    Image(systemName: "doc.text")
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 20)

            if !isSaveGame {
                GroupBoxTV {
                    VStack(spacing: 20) {
                        Button {
                            loadUrl = urlProvider?.urlExampleData(isGerman: false)
                        } label: {
                            Label { Text("English Data", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                        }
                        .padding(.top, 12)

                        Button {
                            loadUrl = urlProvider?.urlExampleData(isGerman: true)
                        } label: {
                            Label { Text("German Data", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                        }

                        Text("Explanation data packages to see how the app works. It explain with real data how to use and add data.", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Import Prebundled Examples", bundle: .module)
                }
                .padding(.bottom, 20)

                @Bindable var bm = importModel
                Picker(selection: $bm.importMode) {
                    Label { Text("Merge", bundle: .module) } icon: { Image(systemName: "arrow.triangle.merge") }
                        .tag(ImportMode.merge)
                    Label { Text("Overwrite", bundle: .module) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .tag(ImportMode.overwrite)
                    Label { Text("Manual", bundle: .module) } icon: { Image(systemName: "list.bullet.clipboard") }
                        .tag(ImportMode.manual)
                } label: {
                    Text("Import Mode", bundle: .module)
                }
                .pickerStyle(.menu)
            }
        }
        .disabled(showImportFileChooser)
    }

    var statusText: some View {
        VStack {
            switch outcome {
            case .notStarted:
                chooseUrlButtons
            case .running:
                Text("Importing \(importModel.importedItems) of \(importModel.totalImportingItems)", bundle: .module)
            case .finished:
                Text("Import is finished, \(importModel.importedItems) are successfully imported.", bundle: .module)
            case .cancelled:
                Text("Import is cancelled, but \(importModel.importedItems) are successfully imported.", bundle: .module)
            case .failed(let message):
                Text(message)
            }
        }
    }
    
    var informationDownloadText: some View {
        GroupBoxTV {
            VStack(spacing: 16) {
                Text("Use the Free Support [Page](https://github.com/Andrenalin/MasterRPG)", bundle: .module)
                Text("These are free packages ready to use. They will add tables with rules, photos, characters and adventures for a certain rule system.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } label: {
            Text("Download free game bundles", bundle: .module)
        }
    }
}

#Preview {
    ImportProgressPanelView(urlProvider: FakeExampleUrlProvider(), importController: FakeImportController.fake)
}

struct FakeExampleUrlProvider: ExampleUrlProvider {
    func urlExampleData(isGerman: Bool) -> URL? {
        nil
    }
}
