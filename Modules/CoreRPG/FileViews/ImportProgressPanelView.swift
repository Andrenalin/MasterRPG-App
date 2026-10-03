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
                .interactiveDismissDisabled(isSessionActive || isApplyingReview)
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
                        if outcome == .notStarted {
                            ImportInformationSection()
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
                                    Text("Ok", bundle: .module)
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
        .onChange(of: initialURL, initial: true) { _, newURL in
            guard let newURL, importRequest == nil, proposedUrl == nil else { return }
            proposedUrl = newURL
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
                await Self.settleReviewFiles(importModel: importModel, rootManager: rootManager)
            }
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
            // The session owns the apply, so a dismissal mid-apply waits for it before the
            // final save and lock release. See CODE_AUDIT_Folder §3.17.
            await session.runApply {
                for module in reviewModel.modules {
                    guard let root = rootManager.rootModel(for: module.id) else { continue }
                    var appliedIds: Set<UUID> = []
                    var deletedIds: Set<UUID> = []
                    for item in module.reviewItems {
                        switch await Self.apply(item: item, root: root) {
                        case .applied: appliedIds.insert(item.id)
                        case .deleted: deletedIds.insert(item.id)
                        case .unchanged: break
                        }
                    }
                    await Self.finishReview(root: root, appliedIds: appliedIds, deletedIds: deletedIds)
                }
            }
            await Self.settleReviewFiles(importModel: importModel, rootManager: rootManager)
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
            await Self.settleReviewFiles(importModel: importModel, rootManager: rootManager)
            navigator.dismiss()
        }
    }

    enum ReviewApplyOutcome {
        case applied, deleted, unchanged
    }

    /// After a module's review items were applied: reviewed deletions go to the trash (and are
    /// purged with link, tag and file cleanup at the next launch) instead of being hard-deleted;
    /// the children of a deleted folder that stay move to root; and the folder repair runs over
    /// everything applied. Hard deletes left dangling folder entries and invisible children.
    /// See CODE_AUDIT_Folder §5.9.
    static func finishReview(root: any ItemRootControllable, appliedIds: Set<UUID>, deletedIds: Set<UUID>) async {
        let editController = root.editControllable
        var detachedIds: Set<UUID> = []
        for itemId in deletedIds {
            guard let item = root.itemControllable.itemSync(for: itemId, noGame: true) else { continue }
            let keptChildren = item.isFolder ? item.entries.map(\.childId).filter {
                !deletedIds.contains($0) && root.itemControllable.itemSync(for: $0, noGame: true)?.parentId == itemId
            } : []
            for childId in keptChildren {
                editController.removeItemFromParent(itemId: childId, oneUp: false, moveFiles: true, scope: .library)
                detachedIds.insert(childId)
            }
            editController.markForDeletion(itemId: itemId)
        }
        let repairIds = appliedIds.union(detachedIds)
        guard !repairIds.isEmpty else { return }
        // One pass over the folders for every applied item. See CODE_AUDIT_Folder §7.3.
        editController.repairFolders(itemIds: appliedIds)
        let repair = ConvertController(itemController: root.itemControllable, editController: editController)
        await repair.repairImportedItems(reportModel: ValidateRepairModel(), importedIds: repairIds)
    }

    /// Settles the files a manual-review parse wrote: those an applied item references stay
    /// (and replace its previous file), the rest are removed. See CODE_AUDIT_Folder §5.2, §5.26.
    static func settleReviewFiles(importModel: ItemDataImportModel, rootManager: RootManager?) async {
        let writes = importModel.reviewFileWrites
        importModel.reviewFileWrites = []
        guard let rootManager else { return }
        for write in writes {
            await rootManager.rootModel(for: write.module)?.itemControllable.settleImportedFile(write.write, itemId: write.itemId)
        }
    }

    func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        guard let importError = error as? ItemDataImportableError else { return false }
        if case .cancel = importError { return true }
        return false
    }

    static func apply(item: ImportReviewItemModel, root: any ItemRootControllable) async -> ReviewApplyOutcome {
        let itemModel = item.itemModel
        if item.isDeletion {
            return itemModel.decision == .imported ? .deleted : .unchanged
        }
        if itemModel.decision == .existing {
            guard itemModel.hasOverrides, itemModel.item.existing != nil else { return .unchanged }
        }
        guard let model = itemModel.materializedItem() as? any Observable & ItemDataAccessible else { return .unchanged }
        // The review was built from the library item as it was at parse time. If it changed
        // while the sheet was open (sync, another window), merge the reviewed result onto the
        // current item instead of overwriting that change. See CODE_AUDIT_Folder §3.17.
        var finalModel: any ModelType = model
        if let parsed = itemModel.item.existing as? any Observable & ItemDataAccessible,
           !root.itemControllable.libraryModel(id: item.id, matches: parsed),
           let merged = root.itemControllable.mergeSync(with: model, forceMerge: true, noGame: true) {
            finalModel = merged
        }
        // A reviewed folder may be a partial copy from a subset export. See CODE_AUDIT_Folder §5.8.
        finalModel = root.itemControllable.keepingLocalFolderChildren(finalModel)
        root.itemControllable.replaceImportedModel(model: finalModel, isInsert: true, forceSave: true)
        return .applied
    }
}

@MainActor @Observable
private final class ImportMutationSession {
    /// The hooks a presenter passes in; plain values the view keeps until it creates the session.
    struct Handlers {
        var beginDataMutation: (@MainActor () -> Bool)?
        var endDataMutation: (@MainActor () async -> Void)?
        var beginSaveDeferral: (@MainActor () -> UUID)?
        var endSaveDeferral: (@MainActor (UUID) -> Void)?
    }

    private let beginDataMutationHandler: (@MainActor () -> Bool)?
    private let endDataMutationHandler: (@MainActor () async -> Void)?
    private let beginSaveDeferral: (@MainActor () -> UUID)?
    private let endSaveDeferral: (@MainActor (UUID) -> Void)?

    private(set) var isActive = false

    var canStartImport: Bool { importTask == nil }

    @ObservationIgnored private var coordinatorToken: UUID?
    /// Held by the session, not the presenting view: release runs from a task that can outlive
    /// the view, and reading the view's `@State` after teardown is not supported.
    /// See CODE_AUDIT_Folder §3.16.
    @ObservationIgnored private var saveDeferralToken: UUID?
    @ObservationIgnored private var importTask: Task<Void, any Error>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    init(handlers: Handlers) {
        self.beginDataMutationHandler = handlers.beginDataMutation
        self.endDataMutationHandler = handlers.endDataMutation
        self.beginSaveDeferral = handlers.beginSaveDeferral
        self.endSaveDeferral = handlers.endSaveDeferral
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
        if saveDeferralToken == nil {
            saveDeferralToken = beginSaveDeferral?()
        }
        return true
    }

    /// Runs the review apply as a task the session owns, so `release` waits for it before the
    /// final save and lock release. See CODE_AUDIT_Folder §3.17.
    func runApply(_ work: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in
            await work()
        }
        applyTask = task
        await task.value
        applyTask = nil
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
        let applyTask = applyTask
        let task = Task { @MainActor [self] in
            _ = await parserTask?.result
            await applyTask?.value
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

        if let saveDeferralToken {
            endSaveDeferral?(saveDeferralToken)
            self.saveDeferralToken = nil
        }
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
        importController: FakeImportController.fake
    )
}

struct FakeExampleUrlProvider: ExampleUrlProvider {
    func urlExampleData(isGerman: Bool) -> URL? {
        nil
    }
}
