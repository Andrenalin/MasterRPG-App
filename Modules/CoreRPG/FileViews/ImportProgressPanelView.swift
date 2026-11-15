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
    public init(importController: any ImportControllable, onImported: (@MainActor (URL) -> Void)? = nil) {
        self.rootManager = nil
        self.urlProvider = nil
        self.importController = importController
        self.isSaveGame = true
        self.initialURL = nil
        self.onImported = onImported
        self.sessionHandlers = ImportMutationSession.Handlers()
    }

    public init(
        rootManager: RootManager?,
        urlProvider: any ExampleUrlProvider,
        importController: any ImportControllable,
        initialURL: URL? = nil,
        beginDataMutationHandler: (@MainActor () -> Bool)? = nil,
        endDataMutationHandler: (@MainActor () async -> Void)? = nil,
        beginSaveDeferral: (@MainActor () -> UUID)? = nil,
        endSaveDeferral: (@MainActor (UUID) -> Void)? = nil
    ) {
        self.rootManager = rootManager
        self.urlProvider = urlProvider
        self.importController = importController
        self.isSaveGame = false
        self.initialURL = initialURL
        self.onImported = nil
        self.sessionHandlers = ImportMutationSession.Handlers(
            beginDataMutation: beginDataMutationHandler,
            endDataMutation: endDataMutationHandler,
            beginSaveDeferral: beginSaveDeferral,
            endSaveDeferral: endSaveDeferral
        )
    }

    let rootManager: RootManager?
    let urlProvider: (any ExampleUrlProvider)?
    let importController: any ImportControllable
    let isSaveGame: Bool
    let initialURL: URL?
    let onImported: (@MainActor (URL) -> Void)?
    private let sessionHandlers: ImportMutationSession.Handlers

    @Environment(\.navigator) private var navigator

    @State private var importModel = ItemDataImportModel()
    @State private var showImportFileChooser = false
    @State private var outcome: ImportOutcome = .notStarted
    @State private var applyErrorMessage: String?
    @State private var isApplyingReview = false
    /// Created when an import first needs it, not in `init`: a `State` initial value is built
    /// on every init of the view, and every one but the first was discarded.
    /// See CODE_AUDIT_Folder §8.2.
    @State private var mutationSession: ImportMutationSession?

    /// The file to import and which attempt this is. Keyed on the URL alone, picking the same
    /// file again after a failed import did not restart the task. See CODE_AUDIT_Folder §8.6.
    @State private var importRequest: ImportRequest?
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
                // The review holds no mutation session (see the parse task), so it is not what
                // keeps the sheet up: an open review is never swiped away with its decisions.
                .interactiveDismissDisabled()
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
                            loadUrl: loadUrlBinding,
                            proposedUrl: $proposedUrl,
                            urlProvider: urlProvider,
                            isSaveGame: isSaveGame
                        )
                        // The free bundles are `.gmz` packages, which a saved game cannot import.
                        if outcome == .notStarted, !isSaveGame {
                            ImportInformationSection { fileUrl in
                                // The person chose the file in the browser: start its import.
                                startImport(of: fileUrl)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedSurface()
                    .navigationTitle(Text("Importing", bundle: .module))
                    .navigationBarTitleDisplayModeAll(.inline)
                    .task(id: importRequest) {
                        guard let loadUrl = importRequest?.url else { return }
                        guard beginDataMutation() else {
                            outcome = .failed(dataMutationUnavailableMessage)
                            return
                        }
                        guard session.canStartImport else {
                            outcome = .failed(dataMutationUnavailableMessage)
                            return
                        }

                        outcome = .running
                        let task = importController.importUrl(
                            from: loadUrl, importModel: importModel, gameMemoryOnly: isSaveGame)
                        guard session.trackImportTask(task) else {
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
                            // Merge and overwrite imports finished mutating during the parse. A
                            // manual import has only built its review snapshot and changed nothing
                            // in the library yet: its session ends here as well, and Apply takes a
                            // new one. Held for as long as the review sheet stayed open, the lock
                            // kept every CloudKit change out of memory and made every package of a
                            // running game wait. Apply merges onto whatever changed meanwhile.
                            // See CODE_AUDIT_21 §3.5, CODE_AUDIT_Folder §3.17.
                            outcome = .finalizing
                            await endDataMutation()
                            outcome = .finished
                        case .failure(let error):
                            outcome = .finalizing
                            await endDataMutation()
                            outcome =
                                isCancellation(error)
                                ? .cancelled : .failed(error.localizedDescription)
                        }
                    }
                    .interactiveDismissDisabled(isSessionActive)

                    #if !os(tvOS)
                        .fileImporter(
                            isPresented: $showImportFileChooser,
                            allowedContentTypes: [isSaveGame ? .gmsDocument : .rpgDocument]
                        ) { result in
                            // A cancelled picker does not call back; a failure is reported.
                            switch result {
                            case .success(let url):
                                startImport(of: url)
                                outcome = .running
                            case .failure(let error):
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
                                    Text("OK", bundle: .module)
                                } icon: {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .disabled(importModel.isImportRunning || isSessionActive)
                        }
                    }
                }
                .themedSurface()
            }
        }
        .onChange(of: initialURL, initial: true) { _, newUrl in
            guard let newUrl, importRequest == nil, proposedUrl == nil else { return }
            proposedUrl = newUrl
            importModel.importMode = .manual
        }
        .onChange(of: outcome, initial: false) { old, new in
            guard old != .finished, new == .finished, let loadUrl = importRequest?.url else { return }
            onImported?(loadUrl)
        }
        .onDisappear {
            mutationSession?.cancelImportAndReleaseInBackground()
            let session = mutationSession
            let importModel = importModel
            let rootManager = rootManager
            Task { @MainActor in
                // After the release (which waits for the parse): remove files a review that was
                // never applied wrote. See CODE_AUDIT_Folder §5.2.
                await session?.release(cancelImport: true)
                await ImportReviewApplyController.settleReviewFiles(importModel: importModel, rootManager: rootManager)
            }
        }
    }
}

private extension ImportProgressPanelView {
    func applyReview() async {
        guard !isApplyingReview else { return }
        isApplyingReview = true
        outcome = .finalizing

        // The review ran without the lock, so another import or a repair can hold it now: the
        // review stays open and Apply can be tried again. See CODE_AUDIT_21 §3.5.
        guard beginDataMutation() else {
            applyErrorMessage = dataMutationUnavailableMessage
            outcome = .finished
            isApplyingReview = false
            return
        }

        if let reviewModel = importModel.reviewModel, let rootManager {
            // The session owns the apply, so a dismissal mid-apply waits for it before the
            // final save and lock release. See CODE_AUDIT_Folder §3.17.
            await session.runApply {
                await ImportReviewApplyController.applyAll(reviewModel: reviewModel, rootManager: rootManager)
            }
            await ImportReviewApplyController.settleReviewFiles(importModel: importModel, rootManager: rootManager)
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

    struct ImportRequest: Equatable {
        let url: URL
        let attempt: Int
    }

    /// `loadUrl` for the sections that choose a file: every set is a new attempt.
    var loadUrlBinding: Binding<URL?> {
        Binding {
            importRequest?.url
        } set: { url in
            guard let url else {
                importRequest = nil
                return
            }
            startImport(of: url)
        }
    }

    func startImport(of url: URL) {
        importRequest = ImportRequest(url: url, attempt: (importRequest?.attempt ?? 0) + 1)
    }

    var isSessionActive: Bool {
        mutationSession?.isActive ?? false
    }

    /// The mutation session, created on first use. Only called from actions and tasks, never
    /// while `body` is evaluated.
    var session: ImportMutationSession {
        if let mutationSession { return mutationSession }
        let session = ImportMutationSession(handlers: sessionHandlers)
        mutationSession = session
        return session
    }

    func beginDataMutation() -> Bool {
        session.beginDataMutation()
    }

    func endDataMutation() async {
        await mutationSession?.release(cancelImport: false)
    }

    func cancelAndDismiss() {
        outcome = .finalizing
        if importModel.isReviewReady {
            isApplyingReview = true
        }
        let importModel = importModel
        let rootManager = rootManager
        Task { @MainActor in
            await mutationSession?.release(cancelImport: true)
            // Files the parse wrote for a review that is now cancelled. See CODE_AUDIT_Folder §5.2.
            await ImportReviewApplyController.settleReviewFiles(importModel: importModel, rootManager: rootManager)
            navigator.dismiss()
        }
    }

    func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        guard let importError = error as? ItemDataImportableError else { return false }
        if case .cancel = importError { return true }
        return false
    }
}

#Preview {
    ImportProgressPanelView(
        rootManager: nil,
        urlProvider: FakeExampleUrlProvider(),
        importController: FakeImportController.fake
    )
}

struct FakeExampleUrlProvider: ExampleUrlProvider {
    func urlExampleData(isGerman: Bool) -> URL? {
        nil
    }
}
