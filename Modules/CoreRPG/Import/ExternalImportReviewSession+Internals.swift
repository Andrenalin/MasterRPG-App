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
                    try await controller.deleteForExternalImport(itemId: mutation.itemId)
                }
            } catch {
                errors.append(
                    "Could not restore \(mutation.module.title) item \(mutation.itemId.uuidString): \(error.localizedDescription)"
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
