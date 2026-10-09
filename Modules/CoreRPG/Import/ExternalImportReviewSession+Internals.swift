// @copyright André Trettin

import Foundation

extension ExternalImportReviewSession {
    // MARK: - Decision Keys & Rollback Recording

    struct DecisionKey: Hashable {
        let module: NetworkModules
        let itemId: UUID
    }

    static func key(for item: ExternalImportBatchItem) -> DecisionKey {
        DecisionKey(module: item.module, itemId: item.id)
    }

    static func decisionKey(for item: ExternalImportBatchItem) -> DecisionKey {
        DecisionKey(module: item.module, itemId: item.decisionOwnerID ?? item.id)
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
        let itemId: UUID
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
            sourceItems = controller.model.sourceItems
            pendingAffectedSourceIDs = controller.model.pendingAffectedSourceIds
        }

        let model: LinkRegisterListModel
        let items: [UUID: [LinkRegisterModel]]
        let sourceItems: [UUID: [LinkRegisterModel]]
        let pendingAffectedSourceIDs: Set<UUID>

        @MainActor
        func restore() {
            let repairAffectedIDs = model.pendingAffectedSourceIds
            model.restoreSnapshot(
                items: items,
                sourceItems: sourceItems,
                pendingAffectedSourceIds: pendingAffectedSourceIDs.union(repairAffectedIDs)
            )
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

    /// The items the import repair of one module can change, taken before the repair runs and
    /// again after it. Rollback restores an item only if it still looks as the repair left it,
    /// so a write by sync or a game during the commit is not reverted. See CODE_AUDIT_Folder §3.6.
    struct RepairSnapshot {
        let module: NetworkModules
        let beforeRepair: [UUID: any ModelType]
        var afterRepair: [UUID: any ModelType]?
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

    // MARK: - Validation & Attachment

    func validatedSelectedItems(rootManager: RootManager) throws -> [ExternalImportBatchItem] {
        var seen: Set<DecisionKey> = []
        var attachmentFileIDs: Set<UUID> = []
        let selectedItems = batch.items.filter { decision(for: $0) != .skip }
        for item in selectedItems {
            let key = Self.key(for: item)
            guard seen.insert(key).inserted else {
                throw ExternalImportError.duplicateItem(itemId: item.id, module: item.module)
            }
            guard Self.supportedModuleOrder.contains(item.module),
                  rootManager.rootModel(for: item.module) != nil else {
                throw ExternalImportError.unsupportedModule(item.module)
            }
            guard item.modelID == item.id, item.modelModule == item.module else {
                throw ExternalImportError.incompatibleModel(itemId: item.id, module: item.module)
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
            throw ExternalImportError.incompatibleModel(itemId: item.id, module: item.module)
        }
        return copy
    }

    func attach(
        _ attachment: ExternalImportAttachment,
        to model: any ModelType,
        item: ExternalImportBatchItem,
        existingModel: (any ModelType)?,
        fileController: FileUrlDataController,
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

        // Loaded for this item only and released when `attach` returns: every attachment id
        // belongs to one item, so a commit-wide cache was never hit and held every converted
        // file of a large world in memory at once. See CODE_AUDIT_Folder §7.2.
        let loaded = try await loadAndValidate(attachment)
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
            module: item.module.token,
            contentHash: loaded.contentHash
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
        // Verified with the hash streamed from disk, not by reading the installed file back
        // into memory. See CODE_AUDIT_Folder §7.2.
        guard try await fileController.contentHash(for: stored) == loaded.contentHash else {
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

    func loadAndValidate(_ attachment: ExternalImportAttachment) async throws -> LoadedAttachment {
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
        // Off the main actor; the transient file below reuses it. See CODE_AUDIT_Folder §7.1.
        let hash = await FileUrl.computeContentHash(of: data)
        if let expectedHash = attachment.contentHash, hash != expectedHash {
            throw ExternalImportError.attachmentHashMismatch(attachmentID: attachment.id)
        }
        return LoadedAttachment(data: data, contentHash: hash)
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
        // Streamed from disk, not loaded whole. See CODE_AUDIT_Folder §7.1.
        guard existing.contentHash == nil,
              let existingHash = try? await fileController.contentHash(for: existing),
              existingHash == expectedHash else { return nil }
        existing.resetContentHash(existingHash)
        return existing
    }

    func modelByAttaching(
        _ fileUrl: FileUrl,
        to model: any ModelType,
        item: ExternalImportBatchItem
    ) throws -> any ModelType {
        guard let updated = item.attaching(fileUrl, to: model) else {
            throw ExternalImportError.incompatibleModel(itemId: item.id, module: item.module)
        }
        return updated
    }

    // MARK: - Rollback

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
                errors.append(String(localized: "Could not restore \(repairSnapshot.module.title) repair state: controller unavailable.", bundle: .module))
                continue
            }
            for (itemId, model) in repairSnapshot.beforeRepair {
                // Nothing to undo, or another writer changed the item after the repair: keep
                // the current state instead of reverting someone else's change.
                if controller.libraryModel(id: itemId, matches: model) { continue }
                if let afterRepair = repairSnapshot.afterRepair,
                   !controller.libraryModel(id: itemId, matches: afterRepair[itemId]) {
                    continue
                }
                do {
                    try controller.replaceForExternalImport(model: model, isInsert: true)
                } catch {
                    errors.append(
                        String(localized: "Could not restore \(repairSnapshot.module.title) item after repair: \(error.localizedDescription)", bundle: .module)
                    )
                }
            }
        }

        for mutation in mutations.reversed() {
            guard let controller = rootManager.rootModel(for: mutation.module)?.itemControllable else {
                errors.append(String(localized: "Could not restore \(mutation.module.title) item: controller unavailable.", bundle: .module))
                continue
            }
            do {
                if let previousModel = mutation.previousModel {
                    try controller.replaceForExternalImport(model: previousModel, isInsert: true)
                } else {
                    try await controller.deleteForExternalImport(itemId: mutation.itemId)
                }
            } catch {
                errors.append(
                    String(localized: "Could not restore \(mutation.module.title) item \(mutation.itemId.uuidString): \(error.localizedDescription)", bundle: .module)
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
                errors.append(String(localized: "Could not remove \(created.fileUrl.rawUrl.lastPathComponent): file controller unavailable.", bundle: .module))
                continue
            }
            do {
                try await deleteCreatedFile(created.fileUrl, using: fileController)
            } catch {
                errors.append(String(localized: "Could not remove \(created.fileUrl.rawUrl.lastPathComponent): \(error.localizedDescription)", bundle: .module))
            }
        }
        return errors
    }

    /// Removes a file this import wrote, found by where the app stores it. It used to resolve
    /// through `url(for:)`, which prefers the temp copy of held peer bytes and then the
    /// bookmark: for a legacy `.icloud` or `.other` reference that is the user's own file
    /// outside the app's storage. Such a reference has no stored location and nothing is
    /// removed for it. See CODE_AUDIT_21 §5.13.
    func deleteCreatedFile(
        _ fileUrl: FileUrl,
        using fileController: FileUrlDataController
    ) async throws {
        if let location = fileController.storedLocation(of: fileUrl) {
            guard await fileController.removeFileLoggingFailure(at: location) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        fileController.removeBookmarks(fileId: fileUrl.fileId)
    }

    /// Removes the file an imported attachment replaced, unless a library item references it:
    /// the item itself when its new reference resolves to the same place, or another item
    /// that shares the file. Only a file in the app's own storage is ever removed, and the
    /// bookmark is left alone: a replacement can carry the same file id.
    /// See CODE_AUDIT_21 §5.13.
    @MainActor
    func deleteSupersededFile(
        _ fileUrl: FileUrl,
        itemControllable: any ItemControllable,
        using fileController: FileUrlDataController
    ) async {
        let isReferenced = itemControllable.libraryFileUrls().contains {
            fileController.isSameStoredFile($0, fileUrl)
        }
        guard !isReferenced else { return }
        await fileController.removeStoredFile(fileUrl)
    }
}
