// @copyright André Trettin

import Foundation
import Observation
import os.log

// MARK: - Review Session

@MainActor @Observable
public final class ExternalImportReviewSession {
    public init(batch: ExternalImportBatch, defaultDecision: ExternalImportDecision = .merge) {
        self.batch = batch
        var decisions: [DecisionKey: ExternalImportDecision] = [:]
        for item in batch.items {
            decisions[Self.decisionKey(for: item)] = defaultDecision
        }
        self.decisions = decisions
    }

    public let batch: ExternalImportBatch
    public private(set) var phase: ExternalImportPhase = .reviewing
    public private(set) var completedItemCount = 0
    public private(set) var selectedItemCount = 0
    public private(set) var result: ExternalImportResult?
    public private(set) var errorDescription: String?
    public var isDecisionEditingEnabled: Bool {
        phase == .reviewing || phase == .failed || phase == .cancelled
    }

    private var decisions: [DecisionKey: ExternalImportDecision]
    private var conflictStatuses: [DecisionKey: ExternalImportConflictStatus] = [:]

    public func decision(for item: ExternalImportBatchItem) -> ExternalImportDecision {
        decisions[Self.decisionKey(for: item)] ?? .skip
    }

    public func setDecision(_ decision: ExternalImportDecision, for item: ExternalImportBatchItem) {
        guard isDecisionEditingEnabled else { return }
        decisions[Self.decisionKey(for: item)] = decision
    }

    public func setDecisionForAll(_ decision: ExternalImportDecision) {
        guard isDecisionEditingEnabled else { return }
        for item in batch.items {
            decisions[Self.decisionKey(for: item)] = decision
        }
    }

    public func conflictStatus(for item: ExternalImportBatchItem) -> ExternalImportConflictStatus? {
        conflictStatuses[Self.key(for: item)]
    }

    // MARK: - Conflict Preflight

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
                  controller.itemSync(for: item.id, noGame: true) != nil else {
                statuses[Self.key(for: item)] = .new
                continue
            }
            let merged = await controller.merge(with: item.model, forceMerge: true)
            statuses[Self.key(for: item)] = merged == nil && item.attachment == nil
                ? .unchanged
                : .changed
        }
        conflictStatuses = statuses
    }

    // MARK: - Commit

    /// Serializes `commit()` across every `ExternalImportReviewSession` instance, not just
    /// re-entrancy on the same instance. `phase` alone only protects a single session; two
    /// independent sessions committing into the same `RootManager`/`ItemController` at once
    /// could interleave read-merge-write across each other's suspension points. See
    /// CODE_AUDIT.md §3.1.
    @MainActor private static var isCommitInProgress = false

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
        guard !Self.isCommitInProgress else {
            throw ExternalImportError.commitAlreadyRunning
        }
        Self.isCommitInProgress = true
        defer { Self.isCommitInProgress = false }

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

        do {
            for item in orderedItems {
                try Task.checkCancellation()

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
                        throw ExternalImportError.missingFileController(itemId: item.id, module: item.module)
                    }
                    let attachmentResult = try await attach(
                        attachment,
                        to: candidate,
                        item: item,
                        existingModel: existing,
                        fileController: fileController,
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
                    // `attach` suspends. A sync or game write to this item in the meantime would
                    // be overwritten by a candidate built from the earlier read, so the commit
                    // stops and rolls back instead. See CODE_AUDIT_Folder §3.6.
                    guard itemController.libraryModel(id: item.id, matches: previous) else {
                        throw ExternalImportError.itemChangedDuringImport(itemId: item.id, module: item.module)
                    }
                }

                if mergedWasUnchanged && !attachmentChanged {
                    accumulator.unchangedItemCount += 1
                    completedItemCount += 1
                    continue
                }

                mutations.append(
                    AppliedMutation(module: item.module, itemId: item.id, previousModel: previous)
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
            phase = .repairing
            for module in Self.supportedModuleOrder {
                try Task.checkCancellation()
                guard let importedIDs = accumulator.importedItemIDs[module], !importedIDs.isEmpty,
                      let root = rootManager.rootModel(for: module) else { continue }

                // Folder and orphan repair can update parents/children which were not
                // selected for import. Capture the items it can reach, plus the shared
                // auxiliary indexes, before allowing those legacy editor operations to run;
                // a snapshot of the whole module made rollback revert unrelated items that
                // changed during the commit. See CODE_AUDIT_Folder §3.6.
                let repairScope = root.itemControllable.externalImportRepairScope(importedIds: importedIDs)
                repairSnapshots.append(
                    RepairSnapshot(
                        module: module,
                        beforeRepair: root.itemControllable.externalImportSnapshots(ids: repairScope),
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
                repairSnapshots[repairSnapshots.count - 1].afterRepair =
                    root.itemControllable.externalImportSnapshots(ids: repairScope)
                try failureReporter.rethrowRecordedError()
                try Task.checkCancellation()
            }

            phase = .saving
            try await consolidatedSave()
            try Task.checkCancellation()

            // The new models and binaries are durable now. Only at this point is it safe to
            // remove binaries replaced by this import; rollback can no longer restore them.
            // Run in an unstructured task: a cancellation arriving now must not leave the
            // replaced files behind. See CODE_AUDIT_Folder §3.1.
            await Task { @MainActor in
                for superseded in supersededFiles {
                    guard let fileController = rootManager.rootModel(for: superseded.module)?
                        .itemControllable.fileUrlDataController else { continue }
                    do {
                        try await self.deleteCreatedFile(superseded.fileUrl, using: fileController)
                    } catch {
                        // The import itself already committed durably; a failed cleanup here
                        // is an orphaned file on disk, not data loss. Log it so it's diagnosable
                        // instead of vanishing silently. See CODE_AUDIT.md §5.2.
                        Logger.importController.error("ExternalImport: failed to delete superseded file \(superseded.fileUrl.fileId, privacy: .public): \(error.localizedDescription, privacy: .private)")
                    }
                }
            }.value

            let finalResult = accumulator.result
            result = finalResult
            phase = .completed
            return finalResult
        } catch {
            let originalError = error
            phase = .rollingBack
            // Persist restored snapshots only when commit actually mutated
            // something. Cancellation before the first item remains write-free.
            let needsSave = !mutations.isEmpty || !repairSnapshots.isEmpty || !createdFiles.isEmpty
            // The rollback runs in an unstructured task, which does not inherit the
            // cancellation that may have caused it: every created-file removal goes through
            // coordinated file access, which refuses to start in a cancelled task, so a user
            // cancel left the installed attachments behind. See CODE_AUDIT_Folder §3.1.
            let rollbackErrors = await Task { @MainActor [mutations, repairSnapshots, createdFiles] in
                var errors = await self.rollback(
                    mutations: mutations,
                    repairSnapshots: repairSnapshots,
                    createdFiles: createdFiles,
                    rootManager: rootManager
                )
                if needsSave {
                    do {
                        try await consolidatedSave()
                    } catch {
                        errors.append("Could not persist restored models: \(error.localizedDescription)")
                    }
                }
                return errors
            }.value
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
