// @copyright André Trettin

import Foundation
import Observation

/// Identifies where a staged external item came from without coupling CoreRPG to
/// a particular importer (Foundry, another VTT, or a future interchange format).
public struct ExternalImportProvenance: Hashable, Codable, Sendable {
    public init(
        source: String,
        sourceScopeID: UUID? = nil,
        packageIdentifier: String? = nil,
        documentIdentifier: String? = nil,
        sourcePath: String? = nil,
        sourceVersion: String? = nil
    ) {
        self.source = source
        self.sourceScopeID = sourceScopeID
        self.packageIdentifier = packageIdentifier
        self.documentIdentifier = documentIdentifier
        self.sourcePath = sourcePath
        self.sourceVersion = sourceVersion
    }

    public let source: String
    /// Stable registry identity; mutable hashes and filenames must not be used as item identity.
    public let sourceScopeID: UUID?
    public let packageIdentifier: String?
    public let documentIdentifier: String?
    public let sourcePath: String?
    public let sourceVersion: String?
}

/// Binary data associated with one staged item. The loader is deliberately lazy:
/// staging and review never read or install attachment bytes.
public struct ExternalImportAttachment: Identifiable, Sendable {
    public typealias Loader = @Sendable () async throws -> Data

    public init(
        id: UUID = UUID(),
        fileID: UUID? = nil,
        suggestedFilename: String,
        contentTypeIdentifier: String? = nil,
        expectedByteCount: Int? = nil,
        contentHash: String? = nil,
        load: @escaping Loader
    ) {
        self.id = id
        self.fileID = fileID ?? id
        self.suggestedFilename = suggestedFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.expectedByteCount = expectedByteCount
        self.contentHash = contentHash
        self.loader = load
    }

    public init(
        id: UUID = UUID(),
        fileID: UUID? = nil,
        suggestedFilename: String,
        contentTypeIdentifier: String? = nil,
        data: Data
    ) {
        let hash = FileUrl.contentHash(of: data)
        self.init(
            id: id,
            fileID: fileID,
            suggestedFilename: suggestedFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            expectedByteCount: data.count,
            contentHash: hash,
            load: { data }
        )
    }

    public let id: UUID
    public let fileID: UUID
    public let suggestedFilename: String
    public let contentTypeIdentifier: String?
    public let expectedByteCount: Int?
    /// Base-64 encoded SHA-256, matching `FileUrl.contentHash`.
    public let contentHash: String?

    private let loader: Loader

    public func load() async throws -> Data {
        try await loader()
    }
}

/// One fully converted domain model waiting for review. Creating this value must
/// not insert the model or write its optional attachment.
public struct ExternalImportBatchItem: Identifiable, Sendable {
    @MainActor
    public init<Model>(
        id: UUID,
        module: NetworkModules,
        name: String,
        model: Model,
        provenance: ExternalImportProvenance,
        attachment: ExternalImportAttachment? = nil,
        warnings: [String] = []
    ) where Model: ItemDataAccessable & Observable {
        self.id = id
        self.module = module
        self.name = name
        self.model = model
        self.modelID = model.id
        self.modelModule = Model.typeId
        self.provenance = provenance
        self.attachment = attachment
        self.warnings = warnings
        self.modelCopier = { candidate in
            guard let candidate = candidate as? Model else { return nil }
            return candidate.copy()
        }
        self.fileUrlReader = { candidate in
            (candidate as? Model)?.fileUrl
        }
        self.fileUrlWriter = { candidate, fileUrl in
            guard var candidate = candidate as? Model else { return nil }
            candidate.fileUrl = fileUrl
            return candidate
        }
    }

    public let id: UUID
    public let module: NetworkModules
    public let name: String
    public let model: any ModelType
    public let modelID: UUID
    public let modelModule: NetworkModules
    public let provenance: ExternalImportProvenance
    public let attachment: ExternalImportAttachment?
    public let warnings: [String]

    private let modelCopier: @MainActor @Sendable (any ModelType) -> (any ModelType)?
    private let fileUrlReader: @MainActor @Sendable (any ModelType) -> FileUrl?
    private let fileUrlWriter: @MainActor @Sendable (any ModelType, FileUrl) -> (any ModelType)?

    @MainActor
    fileprivate func copy(_ candidate: any ModelType) -> (any ModelType)? {
        modelCopier(candidate)
    }

    @MainActor
    fileprivate func fileUrl(from candidate: (any ModelType)?) -> FileUrl? {
        guard let candidate else { return nil }
        return fileUrlReader(candidate)
    }

    @MainActor
    fileprivate func attaching(_ fileUrl: FileUrl, to candidate: any ModelType) -> (any ModelType)? {
        fileUrlWriter(candidate, fileUrl)
    }
}

/// A partial, additive external import. Absence from this batch never means that
/// a local model should be deleted.
public struct ExternalImportBatch: Identifiable, Sendable {
    public init(
        id: UUID = UUID(),
        title: String,
        provenance: ExternalImportProvenance,
        items: [ExternalImportBatchItem],
        warnings: [String] = []
    ) {
        self.id = id
        self.title = title
        self.provenance = provenance
        self.items = items
        self.warnings = warnings
    }

    public let id: UUID
    public let title: String
    public let provenance: ExternalImportProvenance
    public let items: [ExternalImportBatchItem]
    public let warnings: [String]

    /// External imports intentionally have partial scope. The commit API has no
    /// deletion decision and does not compare this list with the local library.
    public var isPartial: Bool { true }
}

public enum ExternalImportDecision: String, CaseIterable, Hashable, Codable, Sendable {
    case skip
    case merge
    case replace
}

public enum ExternalImportConflictStatus: String, Equatable, Sendable {
    case new
    case unchanged
    case changed
}

public enum ExternalImportPhase: Equatable, Sendable {
    case reviewing
    case committing
    case repairing
    case saving
    case rollingBack
    case completed
    case failed
    case cancelled
}

public struct ExternalImportResult: Equatable, Sendable {
    public init(
        insertedItemCount: Int,
        mergedItemCount: Int,
        replacedItemCount: Int,
        unchangedItemCount: Int,
        skippedItemCount: Int,
        installedAttachmentCount: Int,
        reusedAttachmentCount: Int,
        importedItemIDs: [NetworkModules: Set<UUID>]
    ) {
        self.insertedItemCount = insertedItemCount
        self.mergedItemCount = mergedItemCount
        self.replacedItemCount = replacedItemCount
        self.unchangedItemCount = unchangedItemCount
        self.skippedItemCount = skippedItemCount
        self.installedAttachmentCount = installedAttachmentCount
        self.reusedAttachmentCount = reusedAttachmentCount
        self.importedItemIDs = importedItemIDs
    }

    public let insertedItemCount: Int
    public let mergedItemCount: Int
    public let replacedItemCount: Int
    public let unchangedItemCount: Int
    public let skippedItemCount: Int
    public let installedAttachmentCount: Int
    public let reusedAttachmentCount: Int
    public let importedItemIDs: [NetworkModules: Set<UUID>]
}

public enum ExternalImportError: LocalizedError, Equatable, Sendable {
    case commitAlreadyRunning
    case commitAlreadyCompleted
    case duplicateItem(itemID: UUID, module: NetworkModules)
    case unsupportedModule(NetworkModules)
    case incompatibleModel(itemID: UUID, module: NetworkModules)
    case missingFileController(itemID: UUID, module: NetworkModules)
    case attachmentSizeMismatch(attachmentID: UUID, expected: Int, actual: Int)
    case attachmentHashMismatch(attachmentID: UUID)
    case attachmentInstallFailed(attachmentID: UUID)
    case duplicateAttachmentFileID(UUID)
    case rollbackIncomplete(originalError: String, rollbackErrors: [String])

    public var errorDescription: String? {
        switch self {
        case .commitAlreadyRunning:
            "An external import is already running."
        case .commitAlreadyCompleted:
            "This external import has already completed."
        case .duplicateItem(let itemID, let module):
            "Item \(itemID.uuidString) occurs more than once in the \(module.title) import batch."
        case .unsupportedModule(let module):
            "The \(module.title) module cannot receive this import."
        case .incompatibleModel(let itemID, let module):
            "Item \(itemID.uuidString) is not compatible with the \(module.title) module."
        case .missingFileController(let itemID, let module):
            "Item \(itemID.uuidString) has an attachment, but \(module.title) cannot store files."
        case .attachmentSizeMismatch(_, let expected, let actual):
            "Attachment size mismatch: expected \(expected) bytes but loaded \(actual)."
        case .attachmentHashMismatch:
            "Attachment integrity validation failed."
        case .attachmentInstallFailed:
            "The attachment could not be installed."
        case .duplicateAttachmentFileID(let fileID):
            "More than one selected attachment uses file id \(fileID.uuidString)."
        case .rollbackIncomplete(let originalError, let rollbackErrors):
            "The import failed (\(originalError)), and rollback was incomplete: \(rollbackErrors.joined(separator: "; "))"
        }
    }
}

@MainActor @Observable
public final class ExternalImportReviewSession {
    public init(batch: ExternalImportBatch, defaultDecision: ExternalImportDecision = .merge) {
        self.batch = batch
        var decisions: [DecisionKey: ExternalImportDecision] = [:]
        for item in batch.items {
            decisions[Self.key(for: item)] = defaultDecision
        }
        self.decisions = decisions
    }

    public let batch: ExternalImportBatch
    public private(set) var phase: ExternalImportPhase = .reviewing
    public private(set) var completedItemCount = 0
    public private(set) var selectedItemCount = 0
    public private(set) var currentItemID: UUID?
    public private(set) var result: ExternalImportResult?
    public private(set) var errorDescription: String?
    public var isDecisionEditingEnabled: Bool {
        phase == .reviewing || phase == .failed || phase == .cancelled
    }

    private var decisions: [DecisionKey: ExternalImportDecision]
    private var conflictStatuses: [DecisionKey: ExternalImportConflictStatus] = [:]

    public func decision(for item: ExternalImportBatchItem) -> ExternalImportDecision {
        decisions[Self.key(for: item)] ?? .skip
    }

    public func setDecision(_ decision: ExternalImportDecision, for item: ExternalImportBatchItem) {
        guard isDecisionEditingEnabled else { return }
        decisions[Self.key(for: item)] = decision
    }

    public func setDecision(_ decision: ExternalImportDecision, itemID: UUID, module: NetworkModules) {
        guard isDecisionEditingEnabled else { return }
        decisions[DecisionKey(module: module, itemID: itemID)] = decision
    }

    public func setDecisionForAll(_ decision: ExternalImportDecision) {
        guard isDecisionEditingEnabled else { return }
        for item in batch.items {
            decisions[Self.key(for: item)] = decision
        }
    }

    public func conflictStatus(for item: ExternalImportBatchItem) -> ExternalImportConflictStatus? {
        conflictStatuses[Self.key(for: item)]
    }

    /// Computes review-only conflict labels without mutating module controllers.
    public func preflightConflicts(rootManager: RootManager) async throws {
        var statuses: [DecisionKey: ExternalImportConflictStatus] = [:]
        for (index, item) in batch.items.enumerated() {
            try Task.checkCancellation()
            if index.isMultiple(of: 64) {
                await Task.yield()
                try Task.checkCancellation()
            }
            guard let controller = rootManager.rootModel(for: item.module)?.itemControllable,
                  let existing = controller.itemSync(for: item.id, noGame: true) else {
                statuses[Self.key(for: item)] = .new
                continue
            }
            let merged = await controller.merge(with: item.model, forceMerge: true)
            statuses[Self.key(for: item)] = merged == nil && item.attachment == nil
                ? .unchanged
                : .changed
            _ = existing
        }
        conflictStatuses = statuses
    }

    public func commit(
        rootManager: RootManager,
        consolidatedSave: @escaping @Sendable () async throws -> Void
    ) async throws -> ExternalImportResult {
        switch phase {
        case .committing, .repairing, .saving, .rollingBack:
            throw ExternalImportError.commitAlreadyRunning
        case .completed:
            throw ExternalImportError.commitAlreadyCompleted
        case .reviewing, .failed, .cancelled:
            break
        }

        let orderedItems: [ExternalImportBatchItem]
        do {
            orderedItems = try validatedSelectedItems(rootManager: rootManager)
        } catch {
            errorDescription = error.localizedDescription
            phase = error is CancellationError ? .cancelled : .failed
            throw error
        }
        selectedItemCount = orderedItems.count
        completedItemCount = 0
        currentItemID = nil
        result = nil
        errorDescription = nil
        phase = .committing

        var accumulator = ResultAccumulator(
            skippedItemCount: batch.items.count - orderedItems.count
        )
        if orderedItems.isEmpty {
            let finalResult = accumulator.result
            result = finalResult
            phase = .completed
            return finalResult
        }
        var mutations: [AppliedMutation] = []
        var repairSnapshots: [RepairSnapshot] = []
        var createdFiles: [CreatedFile] = []
        var supersededFiles: [CreatedFile] = []
        var loadedAttachments: [UUID: LoadedAttachment] = [:]

        do {
            for item in orderedItems {
                try Task.checkCancellation()
                currentItemID = item.id

                guard let root = rootManager.rootModel(for: item.module) else {
                    throw ExternalImportError.unsupportedModule(item.module)
                }
                let itemController = root.itemControllable
                let existing = itemController.itemSync(for: item.id, noGame: true)
                let previous: (any ModelType)?
                if let existing {
                    previous = try copyModel(existing, for: item)
                } else {
                    previous = nil
                }
                let decision = decision(for: item)
                var candidate: any ModelType
                var mergedWasUnchanged = false

                switch decision {
                case .skip:
                    // Filtered out by `validatedSelectedItems`; retain this case so
                    // a decision mutation during suspension cannot cause a write.
                    accumulator.skippedItemCount += 1
                    completedItemCount += 1
                    continue

                case .replace:
                    candidate = try copyModel(item.model, for: item)

                case .merge:
                    let importedCopy = try copyModel(item.model, for: item)
                    if let merged = await itemController.merge(with: importedCopy, forceMerge: true) {
                        candidate = try copyModel(merged, for: item)
                    } else if item.attachment != nil, let existing {
                        // A model can compare equal while its separately staged
                        // attachment differs. Preserve the model and review the
                        // attachment without manufacturing a model-level merge.
                        candidate = try copyModel(existing, for: item)
                        mergedWasUnchanged = true
                    } else {
                        accumulator.unchangedItemCount += 1
                        completedItemCount += 1
                        continue
                    }
                }

                var attachmentChanged = false
                if let attachment = item.attachment {
                    guard let fileController = itemController.fileUrlDataController else {
                        throw ExternalImportError.missingFileController(itemID: item.id, module: item.module)
                    }
                    let attachmentResult = try await attach(
                        attachment,
                        to: candidate,
                        item: item,
                        existingModel: existing,
                        fileController: fileController,
                        loadedAttachments: &loadedAttachments,
                        createdFiles: &createdFiles
                    )
                    candidate = attachmentResult.model
                    attachmentChanged = attachmentResult.changed
                    if attachmentResult.reused {
                        accumulator.reusedAttachmentCount += 1
                    }
                    if attachmentResult.installed {
                        accumulator.installedAttachmentCount += 1
                    }
                    if let supersededFile = attachmentResult.supersededFile {
                        supersededFiles.append(CreatedFile(module: item.module, fileUrl: supersededFile))
                    }
                }

                if mergedWasUnchanged && !attachmentChanged {
                    accumulator.unchangedItemCount += 1
                    completedItemCount += 1
                    continue
                }

                mutations.append(
                    AppliedMutation(module: item.module, itemID: item.id, previousModel: previous)
                )
                try itemController.replaceForExternalImport(
                    model: candidate,
                    isInsert: existing == nil
                )

                if existing == nil {
                    accumulator.insertedItemCount += 1
                } else if decision == .replace {
                    accumulator.replacedItemCount += 1
                } else {
                    accumulator.mergedItemCount += 1
                }
                accumulator.importedItemIDs[item.module, default: []].insert(item.id)
                completedItemCount += 1
            }

            try Task.checkCancellation()
            currentItemID = nil
            phase = .repairing
            for module in Self.supportedModuleOrder {
                try Task.checkCancellation()
                guard let importedIDs = accumulator.importedItemIDs[module], !importedIDs.isEmpty,
                      let root = rootManager.rootModel(for: module) else { continue }

                // Folder and orphan repair can update parents/children which were not
                // selected for import. Capture the complete surrounding state, plus
                // the shared auxiliary indexes, before allowing those legacy editor
                // operations to run.
                repairSnapshots.append(
                    RepairSnapshot(
                        module: module,
                        models: root.itemControllable.externalImportSnapshots(excluding: importedIDs),
                        linkRegister: LinkRegisterSnapshot(controller: root.editControllable.linkRegisterController),
                        tags: TagSnapshot(controller: root.editControllable.tagController)
                    )
                )
                let repair = ConvertController(
                    itemController: root.itemControllable,
                    editController: root.editControllable
                )
                let failureReporter = ItemPersistenceFailureReporter()
                await ItemPersistenceFailureScope.$reporter.withValue(failureReporter) {
                    await repair.repairImportedItems(
                        reportModel: ValidateRepairModel(total: importedIDs.count, currentModule: module),
                        importedIds: importedIDs
                    )
                }
                try failureReporter.rethrowRecordedError()
                try Task.checkCancellation()
            }

            phase = .saving
            try await consolidatedSave()
            try Task.checkCancellation()

            // The new models and binaries are durable now. Only at this point is it safe to
            // remove binaries replaced by this import; rollback can no longer restore them.
            for superseded in supersededFiles {
                guard let fileController = rootManager.rootModel(for: superseded.module)?
                    .itemControllable.fileUrlDataController else { continue }
                try? await deleteCreatedFile(superseded.fileUrl, using: fileController)
            }

            let finalResult = accumulator.result
            result = finalResult
            phase = .completed
            return finalResult
        } catch {
            let originalError = error
            phase = .rollingBack
            var rollbackErrors = await rollback(
                mutations: mutations,
                repairSnapshots: repairSnapshots,
                createdFiles: createdFiles,
                rootManager: rootManager
            )
            // Persist restored snapshots only when commit actually mutated
            // something. Cancellation before the first item remains write-free.
            if !mutations.isEmpty || !repairSnapshots.isEmpty || !createdFiles.isEmpty {
                do {
                    try await consolidatedSave()
                } catch {
                    rollbackErrors.append("Could not persist restored models: \(error.localizedDescription)")
                }
            }
            currentItemID = nil
            if !rollbackErrors.isEmpty {
                let rollbackError = ExternalImportError.rollbackIncomplete(
                    originalError: originalError.localizedDescription,
                    rollbackErrors: rollbackErrors
                )
                errorDescription = rollbackError.localizedDescription
                phase = .failed
                throw rollbackError
            }
            errorDescription = originalError.localizedDescription
            phase = originalError is CancellationError ? .cancelled : .failed
            throw originalError
        }
    }
}

private extension ExternalImportReviewSession {
    struct DecisionKey: Hashable {
        let module: NetworkModules
        let itemID: UUID
    }

    static func key(for item: ExternalImportBatchItem) -> DecisionKey {
        DecisionKey(module: item.module, itemID: item.id)
    }

    static let supportedModuleOrder: [NetworkModules] = [
        .photo,
        .audio,
        .pdf,
        .space,
        .dice,
        .table,
        .rule,
        .weather,
        .value,
        .map,
        .adventure,
        .generator
    ]

    struct AppliedMutation {
        let module: NetworkModules
        let itemID: UUID
        let previousModel: (any ModelType)?
    }

    struct CreatedFile {
        let module: NetworkModules
        let fileUrl: FileUrl
    }

    struct LinkRegisterSnapshot {
        @MainActor
        init(controller: LinkRegisterController) {
            model = controller.model
            items = controller.model.items
            pendingAffectedSourceIDs = controller.model.pendingAffectedSourceIds
        }

        let model: LinkRegisterListModel
        let items: [UUID: [LinkRegisterModel]]
        let pendingAffectedSourceIDs: Set<UUID>

        @MainActor
        func restore() {
            let repairAffectedIDs = model.pendingAffectedSourceIds
            model.items = items
            model.pendingAffectedSourceIds = pendingAffectedSourceIDs.union(repairAffectedIDs)
        }
    }

    struct TagSnapshot {
        @MainActor
        init(controller: TagController) {
            model = controller.model
            tags = controller.model.tags
            pendingAffectedModules = controller.model.pendingAffectedModules
        }

        let model: TagInternalControllerModel
        let tags: [NetworkModules: [String: TagModel]]
        let pendingAffectedModules: Set<NetworkModules>

        @MainActor
        func restore() {
            let repairAffectedModules = model.pendingAffectedModules
            model.tags = tags
            model.pendingAffectedModules = pendingAffectedModules.union(repairAffectedModules)
        }
    }

    struct RepairSnapshot {
        let module: NetworkModules
        let models: [any ModelType]
        let linkRegister: LinkRegisterSnapshot
        let tags: TagSnapshot
    }

    struct LoadedAttachment {
        let data: Data
        let contentHash: String
    }

    struct AttachmentResult {
        let model: any ModelType
        let changed: Bool
        let reused: Bool
        let installed: Bool
        let supersededFile: FileUrl?
    }

    struct ResultAccumulator {
        var insertedItemCount = 0
        var mergedItemCount = 0
        var replacedItemCount = 0
        var unchangedItemCount = 0
        var skippedItemCount: Int
        var installedAttachmentCount = 0
        var reusedAttachmentCount = 0
        var importedItemIDs: [NetworkModules: Set<UUID>] = [:]

        var result: ExternalImportResult {
            ExternalImportResult(
                insertedItemCount: insertedItemCount,
                mergedItemCount: mergedItemCount,
                replacedItemCount: replacedItemCount,
                unchangedItemCount: unchangedItemCount,
                skippedItemCount: skippedItemCount,
                installedAttachmentCount: installedAttachmentCount,
                reusedAttachmentCount: reusedAttachmentCount,
                importedItemIDs: importedItemIDs
            )
        }
    }

    func validatedSelectedItems(rootManager: RootManager) throws -> [ExternalImportBatchItem] {
        var seen: Set<DecisionKey> = []
        var attachmentFileIDs: Set<UUID> = []
        let selectedItems = batch.items.filter { decision(for: $0) != .skip }
        for item in selectedItems {
            let key = Self.key(for: item)
            guard seen.insert(key).inserted else {
                throw ExternalImportError.duplicateItem(itemID: item.id, module: item.module)
            }
            guard Self.supportedModuleOrder.contains(item.module),
                  rootManager.rootModel(for: item.module) != nil else {
                throw ExternalImportError.unsupportedModule(item.module)
            }
            guard item.modelID == item.id, item.modelModule == item.module else {
                throw ExternalImportError.incompatibleModel(itemID: item.id, module: item.module)
            }
            if let fileID = item.attachment?.fileID,
               !attachmentFileIDs.insert(fileID).inserted {
                throw ExternalImportError.duplicateAttachmentFileID(fileID)
            }
        }

        let order = Dictionary(
            uniqueKeysWithValues: Self.supportedModuleOrder.enumerated().map { ($0.element, $0.offset) }
        )
        return selectedItems.sorted {
            let lhsOrder = order[$0.module, default: Int.max]
            let rhsOrder = order[$1.module, default: Int.max]
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func copyModel(
        _ model: any ModelType,
        for item: ExternalImportBatchItem
    ) throws -> any ModelType {
        guard let copy = item.copy(model) else {
            throw ExternalImportError.incompatibleModel(itemID: item.id, module: item.module)
        }
        return copy
    }

    func attach(
        _ attachment: ExternalImportAttachment,
        to model: any ModelType,
        item: ExternalImportBatchItem,
        existingModel: (any ModelType)?,
        fileController: FileUrlDataController,
        loadedAttachments: inout [UUID: LoadedAttachment],
        createdFiles: inout [CreatedFile]
    ) async throws -> AttachmentResult {
        let existingFileUrl = item.fileUrl(from: existingModel)

        if let expectedHash = attachment.contentHash,
           let reusable = await reusableFileUrl(
               existingFileUrl,
               expectedHash: expectedHash,
               fileController: fileController
           ) {
            let updatedModel = try modelByAttaching(reusable, to: model, item: item)
            return AttachmentResult(
                model: updatedModel,
                changed: existingFileUrl != reusable,
                reused: true,
                installed: false,
                supersededFile: nil
            )
        }

        let loaded = try await loadAndValidate(
            attachment,
            cache: &loadedAttachments
        )
        if let reusable = await reusableFileUrl(
            existingFileUrl,
            expectedHash: loaded.contentHash,
            fileController: fileController
        ) {
            let updatedModel = try modelByAttaching(reusable, to: model, item: item)
            return AttachmentResult(
                model: updatedModel,
                changed: existingFileUrl != reusable,
                reused: true,
                installed: false,
                supersededFile: nil
            )
        }

        var storageID = attachment.fileID
        if existingFileUrl?.fileId == storageID {
            // Never overwrite the prior binary: keeping a distinct file makes
            // rollback of a replaced model recoverable.
            storageID = UUID()
        }
        let baseName = URL(filePath: attachment.suggestedFilename).lastPathComponent
        let safeName = "\(storageID.uuidString)-\(baseName.isEmpty ? "attachment" : baseName)"
        let transient = FileUrl(
            importedData: loaded.data,
            fileId: storageID,
            filename: safeName,
            module: item.module.token
        )
        guard let stored = try await fileController.createNewFileUrl(
            fileId: storageID,
            unconvertedFileUrl: transient,
            pathExtension: URL(filePath: safeName).pathExtension,
            requireDurableStorage: true
        ) else {
            throw ExternalImportError.attachmentInstallFailed(attachmentID: attachment.id)
        }

        // Record ownership immediately after installation. Any later verification,
        // cancellation, or model-attachment failure is handled by the transaction's
        // normal rollback path, whose cleanup failures are retried and reported.
        createdFiles.append(CreatedFile(module: item.module, fileUrl: stored))
        guard let installedData = try await fileController.loadData(for: stored),
              FileUrl.contentHash(of: installedData) == loaded.contentHash else {
            throw ExternalImportError.attachmentInstallFailed(attachmentID: attachment.id)
        }
        let updatedModel = try modelByAttaching(stored, to: model, item: item)
        return AttachmentResult(
            model: updatedModel,
            changed: true,
            reused: false,
            installed: true,
            supersededFile: existingFileUrl
        )
    }

    func loadAndValidate(
        _ attachment: ExternalImportAttachment,
        cache: inout [UUID: LoadedAttachment]
    ) async throws -> LoadedAttachment {
        if let cached = cache[attachment.id] {
            if let expectedByteCount = attachment.expectedByteCount,
               cached.data.count != expectedByteCount {
                throw ExternalImportError.attachmentSizeMismatch(
                    attachmentID: attachment.id,
                    expected: expectedByteCount,
                    actual: cached.data.count
                )
            }
            if let expectedHash = attachment.contentHash,
               cached.contentHash != expectedHash {
                throw ExternalImportError.attachmentHashMismatch(attachmentID: attachment.id)
            }
            return cached
        }
        try Task.checkCancellation()
        let data = try await attachment.load()
        try Task.checkCancellation()
        if let expectedByteCount = attachment.expectedByteCount,
           data.count != expectedByteCount {
            throw ExternalImportError.attachmentSizeMismatch(
                attachmentID: attachment.id,
                expected: expectedByteCount,
                actual: data.count
            )
        }
        let hash = FileUrl.contentHash(of: data)
        if let expectedHash = attachment.contentHash, hash != expectedHash {
            throw ExternalImportError.attachmentHashMismatch(attachmentID: attachment.id)
        }
        let loaded = LoadedAttachment(data: data, contentHash: hash)
        cache[attachment.id] = loaded
        return loaded
    }

    func reusableFileUrl(
        _ existing: FileUrl?,
        expectedHash: String,
        fileController: FileUrlDataController
    ) async -> FileUrl? {
        guard Data(base64Encoded: expectedHash)?.count == 32 else { return nil }
        guard var existing else { return nil }
        if existing.contentHash == expectedHash {
            return await fileController.hasLocalData(for: existing) ? existing : nil
        }
        guard existing.contentHash == nil,
              let data = try? await fileController.loadData(for: existing),
              FileUrl.contentHash(of: data) == expectedHash else { return nil }
        existing.resetContentHash(of: data)
        return existing
    }

    func modelByAttaching(
        _ fileUrl: FileUrl,
        to model: any ModelType,
        item: ExternalImportBatchItem
    ) throws -> any ModelType {
        guard let updated = item.attaching(fileUrl, to: model) else {
            throw ExternalImportError.incompatibleModel(itemID: item.id, module: item.module)
        }
        return updated
    }

    func rollback(
        mutations: [AppliedMutation],
        repairSnapshots: [RepairSnapshot],
        createdFiles: [CreatedFile],
        rootManager: RootManager
    ) async -> [String] {
        var errors: [String] = []

        // Repair may change unselected parent/child models. Restore those exact
        // snapshots first; imported models are restored by `mutations` below.
        for repairSnapshot in repairSnapshots.reversed() {
            guard let controller = rootManager.rootModel(for: repairSnapshot.module)?.itemControllable else {
                errors.append("Could not restore \(repairSnapshot.module.title) repair state: controller unavailable.")
                continue
            }
            for model in repairSnapshot.models {
                do {
                    try controller.replaceForExternalImport(model: model, isInsert: true)
                } catch {
                    errors.append(
                        "Could not restore \(repairSnapshot.module.title) item after repair: \(error.localizedDescription)"
                    )
                }
            }
        }

        for mutation in mutations.reversed() {
            guard let controller = rootManager.rootModel(for: mutation.module)?.itemControllable else {
                errors.append("Could not restore \(mutation.module.title) item: controller unavailable.")
                continue
            }
            do {
                if let previousModel = mutation.previousModel {
                    try controller.replaceForExternalImport(model: previousModel, isInsert: true)
                } else {
                    try await controller.deleteForExternalImport(itemId: mutation.itemID)
                }
            } catch {
                errors.append(
                    "Could not restore \(mutation.module.title) item \(mutation.itemID.uuidString): \(error.localizedDescription)"
                )
            }
        }

        // Restore auxiliary state only after every item snapshot is back in place.
        // Keep all affected IDs/modules pending so the rollback save reverses a
        // repair that may already have been flushed before the original failure.
        for repairSnapshot in repairSnapshots.reversed() {
            repairSnapshot.linkRegister.restore()
            repairSnapshot.tags.restore()
        }

        for created in createdFiles.reversed() {
            guard let fileController = rootManager.rootModel(for: created.module)?
                .itemControllable.fileUrlDataController else {
                errors.append("Could not remove \(created.fileUrl.rawUrl.lastPathComponent): file controller unavailable.")
                continue
            }
            do {
                try await deleteCreatedFile(created.fileUrl, using: fileController)
            } catch {
                errors.append("Could not remove \(created.fileUrl.rawUrl.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return errors
    }

    func deleteCreatedFile(
        _ fileUrl: FileUrl,
        using fileController: FileUrlDataController
    ) async throws {
        let removed = try await fileController.url(for: fileUrl) { url async throws -> Bool? in
            guard let url else { return false }
            do {
                try await FileManager.default.removeItem(coordinatingAccessAt: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return true
            }
            return true
        } ?? false
        guard removed else {
            throw CocoaError(.fileNoSuchFile)
        }
        fileController.removeBookmarks(fileId: fileUrl.fileId)
    }
}
