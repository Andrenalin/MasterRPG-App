// @copyright André Trettin

import SwiftUI

public protocol ExampleUrlProvider {
    @MainActor func urlExampleData(isGerman: Bool) -> URL?
}

enum ImportOutcome: Equatable, Sendable {
    case notStarted
    case running
    case cancelled
    case finished
    case failed(String)
}

public struct ImportProgressPanelView: View {
    public init(importController: any ImportControllable) {
        self.rootManager = nil
        self.urlProvider = nil
        self.importController = importController
        self.isSaveGame = true
        self.saveDeferredHandler = nil
    }

    public init(rootManager: RootManager?, urlProvider: any ExampleUrlProvider, importController: any ImportControllable, saveDeferredHandler: ((Bool) -> Void)?) {
        self.rootManager = rootManager
        self.urlProvider = urlProvider
        self.importController = importController
        self.isSaveGame = false
        self.saveDeferredHandler = saveDeferredHandler
    }

    let rootManager: RootManager?
    let urlProvider: (any ExampleUrlProvider)?
    let importController: any ImportControllable
    let isSaveGame: Bool
    let saveDeferredHandler: ((Bool) -> Void)?

    @Environment(\.navigator) private var navigator

    @State private var importModel = ItemDataImportModel()
    @State private var showImportFileChooser = false
    @State private var outcome: ImportOutcome = .notStarted

    @State private var loadUrl: URL?
    @State private var importTask: Task<Void, any Error>?

    public var body: some View {
        if importModel.isReviewReady, let reviewModel = importModel.reviewModel {
            ImportReviewSplitView(
                model: reviewModel,
                rootManager: rootManager,
                onCancel: {
                    importTask?.cancel()
                    navigator.dismiss()
                },
                onApply: { await applyReview() }
            )
        } else {
            NavigationStack {
                VStack {
                    ImportProgressSection(importModel: importModel)
                    ImportStatusSection(
                        outcome: outcome,
                        importModel: importModel,
                        showImportFileChooser: $showImportFileChooser,
                        loadUrl: $loadUrl,
                        urlProvider: urlProvider,
                        isSaveGame: isSaveGame
                    )
                    if outcome == .notStarted {
                        ImportInformationSection()
                    }
                }
                .padding()
                .navigationTitle(Text("Importing", bundle: .module))
                .navigationBarTitleDisplayModeAll(.inline)
                .task(id: loadUrl) {
                    guard let loadUrl else { return }
                    do {
                        outcome = .running
                        saveDeferredHandler?(true)
                        defer { saveDeferredHandler?(false) }

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
                        .disabled(outcome == .finished)
                    }
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
}

private extension ImportProgressPanelView {
    func applyReview() async {
        if let reviewModel = importModel.reviewModel, let rootManager {
            for module in reviewModel.modules {
                guard let root = rootManager.rootModel(for: module.id) else { continue }
                for item in module.reviewItems {
                    await apply(item: item, root: root)
                }
            }
        }
        importModel.isReviewReady = false
        importModel.reviewModel = nil
        importModel.pendingModules = [:]
        navigator.dismiss()
    }

    func apply(item: ImportReviewItemModel, root: any ItemRootControllable) async {
        let itemModel = item.itemModel
        if item.isDeletion {
            if itemModel.decision == .imported {
                await root.itemControllable.delete(itemId: item.id)
            }
            return
        }
        if itemModel.decision == .existing {
            guard itemModel.hasOverrides, itemModel.item.existing != nil else { return }
        }
        guard let model = itemModel.materializedItem() as? any Observable & ItemDataAccessable else { return }
        root.itemControllable.replace(model: model, isInsert: true, forceSave: true)
        root.editControllable.repairFolder(itemId: item.id)
    }
}

#Preview {
    ImportProgressPanelView(
        rootManager: nil,
        urlProvider: FakeExampleUrlProvider(),
        importController: FakeImportController.fake,
        saveDeferredHandler: nil
    )
}

struct FakeExampleUrlProvider: ExampleUrlProvider {
    func urlExampleData(isGerman: Bool) -> URL? {
        nil
    }
}
