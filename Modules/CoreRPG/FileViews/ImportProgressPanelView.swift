// @copyright André Trettin

import Foundation
import Observation
import SwiftUI

public protocol ExampleUrlProvider {
    @MainActor func urlExampleData(isGerman: Bool) -> URL?
}

enum ImportOutcome: Equatable, Sendable {
    case notStarted
    case running
    case finalizing
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
        self.initialURL = nil
        _mutationSession = State(initialValue: ImportMutationSession())
    }

    public init(
        rootManager: RootManager?,
        urlProvider: any ExampleUrlProvider,
        importController: any ImportControllable,
        initialURL: URL? = nil,
        beginDataMutationHandler: (@MainActor () -> Bool)? = nil,
        endDataMutationHandler: (@MainActor () async -> Void)? = nil,
        saveDeferredHandler: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.rootManager = rootManager
        self.urlProvider = urlProvider
        self.importController = importController
        self.isSaveGame = false
        self.initialURL = initialURL
        _mutationSession = State(
            initialValue: ImportMutationSession(
                beginDataMutationHandler: beginDataMutationHandler,
                endDataMutationHandler: endDataMutationHandler,
                saveDeferredHandler: saveDeferredHandler
            )
        )
    }

    let rootManager: RootManager?
    let urlProvider: (any ExampleUrlProvider)?
    let importController: any ImportControllable
    let isSaveGame: Bool
    let initialURL: URL?

    @Environment(\.navigator) private var navigator

    @State private var importModel = ItemDataImportModel()
    @State private var showImportFileChooser = false
    @State private var outcome: ImportOutcome = .notStarted
    @State private var applyErrorMessage: String?
    @State private var isApplyingReview = false
    @State private var mutationSession: ImportMutationSession

    @State private var loadUrl: URL?
    @State private var proposedUrl: URL?

    public var body: some View {
        Group {
            if importModel.isReviewReady, let reviewModel = importModel.reviewModel {
                ImportReviewSplitView(
                    model: reviewModel,
                    rootManager: rootManager,
                    isApplying: isApplyingReview,
                    onCancel: {
                        guard !isApplyingReview else { return }
                        cancelAndDismiss()
                    },
                    onApply: { await applyReview() }
                )
                .interactiveDismissDisabled(mutationSession.isActive || isApplyingReview)
                .alert(
                    Text("Import Unavailable", bundle: .module),
                    isPresented: Binding(
                        get: { applyErrorMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                applyErrorMessage = nil
                            }
                        }
                    )
                ) {
                    Button(role: .cancel) {
                        applyErrorMessage = nil
                    } label: {
                        Text("OK", bundle: .module)
                    }
                } message: {
                    Text(verbatim: applyErrorMessage ?? "")
                }
            } else {
                NavigationStack {
                    VStack {
                        ImportProgressSection(
                            importModel: importModel,
                            isFinalizing: outcome == .finalizing
                        )
                        ImportStatusSection(
                            outcome: outcome,
                            importModel: importModel,
                            showImportFileChooser: $showImportFileChooser,
                            loadUrl: $loadUrl,
                            proposedUrl: $proposedUrl,
                            urlProvider: urlProvider,
                            isSaveGame: isSaveGame
                        )
                        if outcome == .notStarted {
                            ImportInformationSection()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedSurface()
                    .navigationTitle(Text("Importing", bundle: .module))
                    .navigationBarTitleDisplayModeAll(.inline)
                    .task(id: loadUrl) {
                        guard let loadUrl else { return }
                        guard beginDataMutation() else {
                            outcome = .failed(dataMutationUnavailableMessage)
                            return
                        }
                        guard mutationSession.canStartImport else {
                            outcome = .failed(dataMutationUnavailableMessage)
                            return
                        }

                        outcome = .running
                        let task = importController.importUrl(
                            from: loadUrl, importModel: importModel)
                        guard mutationSession.trackImportTask(task) else {
                            task.cancel()
                            outcome = .failed(dataMutationUnavailableMessage)
                            return
                        }

                        let result = await withTaskCancellationHandler {
                            await task.result
                        } onCancel: {
                            task.cancel()
                        }

                        switch result {
                        case .success:
                            // A manual import keeps the same exclusive mutation session while the user
                            // reviews its snapshot. Merge/overwrite imports finish mutating during parse.
                            if importModel.isReviewReady && importModel.reviewModel != nil {
                                outcome = .finished
                            } else {
                                outcome = .finalizing
                                await endDataMutation()
                                outcome = .finished
                            }
                        case .failure(let error):
                            outcome = .finalizing
                            await endDataMutation()
                            outcome =
                                isCancellation(error)
                                ? .cancelled : .failed(error.localizedDescription)
                        }
                    }
                    .interactiveDismissDisabled(mutationSession.isActive)

                    #if !os(tvOS)
                        .fileImporter(
                            isPresented: $showImportFileChooser,
                            allowedContentTypes: [isSaveGame ? .gmsDocument : .rpgDocument]
                        ) { result in
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
                                cancelAndDismiss()
                            } label: {
                                Label {
                                    Text("Cancel", bundle: .module)
                                } icon: {
                                    Image(systemName: "xmark")
                                }
                            }
                            .disabled(outcome == .finished || outcome == .finalizing)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                navigator.dismiss()
                            } label: {
                                Label {
                                    Text("Ok", bundle: .module)
                                } icon: {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .disabled(importModel.isImportRunning || mutationSession.isActive)
                        }
                    }
                }
                .themedSurface()
            }
        }
        .onChange(of: initialURL, initial: true) { _, newURL in
            guard let newURL, loadUrl == nil, proposedUrl == nil else { return }
            proposedUrl = newURL
            importModel.importMode = .manual
        }
        .onDisappear {
            mutationSession.cancelImportAndReleaseInBackground()
        }
    }
}

private extension ImportProgressPanelView {
    func applyReview() async {
        guard !isApplyingReview else { return }
        isApplyingReview = true
        outcome = .finalizing

        guard beginDataMutation() else {
            applyErrorMessage = dataMutationUnavailableMessage
            outcome = .finished
            isApplyingReview = false
            return
        }

        if let reviewModel = importModel.reviewModel, let rootManager {
            for module in reviewModel.modules {
                guard let root = rootManager.rootModel(for: module.id) else { continue }
                for item in module.reviewItems {
                    await apply(item: item, root: root)
                }
            }
        }
        await endDataMutation()
        outcome = .finished
        isApplyingReview = false

        importModel.isReviewReady = false
        importModel.reviewModel = nil
        importModel.pendingModules = [:]
        navigator.dismiss()
    }

    var dataMutationUnavailableMessage: String {
        String(
            localized:
                "Another import or repair operation is currently changing RPG data. Try again when it finishes.",
            bundle: .module
        )
    }

    func beginDataMutation() -> Bool {
        mutationSession.beginDataMutation()
    }

    func endDataMutation() async {
        await mutationSession.release(cancelImport: false)
    }

    func cancelAndDismiss() {
        outcome = .finalizing
        if importModel.isReviewReady {
            isApplyingReview = true
        }
        Task { @MainActor in
            await mutationSession.release(cancelImport: true)
            navigator.dismiss()
        }
    }

    func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        guard let importError = error as? ItemDataImportableError else { return false }
        if case .cancel = importError { return true }
        return false
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
        root.itemControllable.replaceImportedModel(model: model, isInsert: true, forceSave: true)
        root.editControllable.repairFolder(itemId: item.id)
    }
}

@MainActor @Observable
private final class ImportMutationSession {
    private let beginDataMutationHandler: (@MainActor () -> Bool)?
    private let endDataMutationHandler: (@MainActor () async -> Void)?
    private let saveDeferredHandler: (@MainActor (Bool) -> Void)?

    private(set) var isActive = false

    var canStartImport: Bool { importTask == nil }

    @ObservationIgnored private var coordinatorToken: UUID?
    @ObservationIgnored private var importTask: Task<Void, any Error>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    init(
        beginDataMutationHandler: (@MainActor () -> Bool)? = nil,
        endDataMutationHandler: (@MainActor () async -> Void)? = nil,
        saveDeferredHandler: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.beginDataMutationHandler = beginDataMutationHandler
        self.endDataMutationHandler = endDataMutationHandler
        self.saveDeferredHandler = saveDeferredHandler
    }

    func beginDataMutation() -> Bool {
        guard !isActive else { return true }

        if let beginDataMutationHandler {
            guard beginDataMutationHandler() else { return false }
        } else {
            guard let token = DataMutationCoordinator.shared.begin() else { return false }
            coordinatorToken = token
        }

        isActive = true
        saveDeferredHandler?(true)
        return true
    }

    /// Retains the parser task so every exit path can wait until parsing has stopped mutating data.
    func trackImportTask(_ task: Task<Void, any Error>) -> Bool {
        guard importTask == nil else { return false }
        importTask = task
        return true
    }

    func release(cancelImport: Bool) async {
        if cancelImport {
            importTask?.cancel()
        }

        if let cleanupTask {
            await cleanupTask.value
            return
        }

        guard isActive else { return }

        let parserTask = importTask
        let task = Task { @MainActor [self] in
            _ = await parserTask?.result
            await self.finishRelease()
        }
        cleanupTask = task
        await task.value
        cleanupTask = nil
    }

    /// SwiftUI disappearance callbacks cannot await. This task deliberately retains the session
    /// until parser cancellation, the final save, and lock release have all completed.
    func cancelImportAndReleaseInBackground() {
        importTask?.cancel()
        guard isActive, cleanupTask == nil else { return }

        Task { @MainActor [self] in
            await self.release(cancelImport: true)
        }
    }

    private func finishRelease() async {
        guard isActive else { return }

        saveDeferredHandler?(false)
        await endDataMutationHandler?()

        if let coordinatorToken {
            DataMutationCoordinator.shared.end(coordinatorToken)
            self.coordinatorToken = nil
        }

        importTask = nil
        isActive = false
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
