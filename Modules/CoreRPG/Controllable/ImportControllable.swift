// @copyright André Trettin

import Foundation
import os.log
import Observation

// MARK: - Protocol

public protocol ImportControllable: Sendable {
    var itemControllable: any ItemControllable { get }
    var editControllable: any EditControllable { get }

    func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws
    func finalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws
}

public enum ItemDataImportableError: Error {
    case openError
    case notEnoughData
    case unsupportedDataType
    case cancel
}

// MARK: - Import Entry Points

public extension ImportControllable {
    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }

    func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {}

    func finalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {}

    // Import from file URL with caller-owned model (progress UI); mode is read from importModel.importMode.
    // `gameMemoryOnly` writes every imported item straight into that module's game memory
    // (`ItemControllable.replaceForGame(policy: .memoryOnly)`), leaving the permanent library and
    // `isGameMode` untouched — used to load a saved game without requiring a game to be running.
    func importUrl(from url: URL, importModel: ItemDataImportModel, gameMemoryOnly: Bool = false) -> Task<Void, any Error> {
        Task(priority: .userInitiated) { @concurrent in
            try await self.performImport(from: url, importModel: importModel, gameMemoryOnly: gameMemoryOnly)
        }
    }

    // Convenience for fire-and-forget callers — no progress UI
    func importUrl(from url: URL) -> Task<Void, any Error> {
        Task(priority: .userInitiated) { @concurrent in
            let importModel = await ItemDataImportModel(importMode: .merge)
            try await self.performImport(from: url, importModel: importModel, gameMemoryOnly: false)
        }
    }

    func importStream(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool = false) async throws {
        // Every cancellation exit throws, so a cancelled import is never reported as finished.
        // See CODE_AUDIT_Folder §3.3.
        try Task.checkCancellation()
        guard inputStream.hasBytesAvailable else { return }

        try await additionalImport(from: inputStream, forceSave: forceSave, importModel: importModel, gameMemoryOnly: gameMemoryOnly)

        let token = await self.token()
        var itemCount = 0
        var version = 0
        while inputStream.hasBytesAvailable {
            try Task.checkCancellation()
            guard let moduleHeader = try inputStream.readOptionalHeader() else { break }
            if moduleHeader.token == token {
                itemCount = moduleHeader.counter
                version = moduleHeader.version
                break
            }
            try await skip(itemCount: moduleHeader.counter, from: inputStream, importModel: importModel)
        }
        guard itemCount > 0 else {
            try await finalImport(
                from: inputStream,
                forceSave: forceSave,
                importModel: importModel,
                gameMemoryOnly: gameMemoryOnly
            )
            return
        }

        await logImport(title: "importStream", count: itemCount, importModel: importModel)

        let policy = await applyPolicy(importModel: importModel, forceSave: forceSave, gameMemoryOnly: gameMemoryOnly)
        let peerPolicy = await importModel.peerPolicy
        var currentFile: Data?
        var importedIds: Set<UUID> = []
        var locallyReusedFileIds: Set<UUID> = []
        var deferredFolderItems: [(item: ModelType, id: UUID)] = []
        // A peer's folders are decided after its other items. See `PeerImportPolicy.admitFolders`.
        var peerFolderItems: [ModelType] = []
        // Folder entries are repaired once for the batch. See CODE_AUDIT_Folder §7.3.
        var folderRepairIds: Set<UUID> = []

        do {
            var counter = 0
            while counter < itemCount {
                try Task.checkCancellation()
                guard inputStream.hasBytesAvailable else { throw ItemDataImportableError.notEnoughData }

                do {
                    let (dataSize, dataToken) = try inputStream.readItemHeader()
                    let data = try inputStream.readData(size: dataSize)

                    switch dataToken {
                    case ExportDataToken.file.rawValue:
                        currentFile = data
                    case ExportDataToken.item.rawValue:
                        counter += 1
                        // A file token belongs to the item that immediately follows it —
                        // consume it here so a later file-less item cannot inherit it.
                        let itemFile = currentFile
                        currentFile = nil
                        do {
                            // decode constructs models, which may be @MainActor — `decode` is
                            // itself `@MainActor`, so `await` alone hops for the decode call
                            // (no `MainActor.run` wrapper needed); the wire format is unchanged.
                            let itemVersion = version
                            let newItem = try await itemControllable.decode(data: data, with: JSONCoding.decoder, version: itemVersion)
                            if peerPolicy != nil, await itemControllable.isFolderImport(newItem) {
                                // A folder skips `prepareDecodedItem`, but its file description
                                // came out of the same bytes. See CODE_AUDIT_24 §6.5.
                                await sanitizeImportedFileUrl(of: newItem, allowsPrivateRemoteHosts: !policy.isUntrustedSource)
                                peerFolderItems.append(newItem)
                                continue
                            }
                            guard await prepareDecodedItem(newItem, allowsPrivateRemoteHosts: !policy.isUntrustedSource, peerPolicy: peerPolicy) else {
                                await recordProcessedItems(importModel, count: 1)
                                continue
                            }
                            var fileWrite: ImportedFileWrite?
                            if let itemFile {
                                let requiresDurableFile = await importModel.requiresDurableFiles
                                let added = try await addFile(
                                    data: itemFile,
                                    to: newItem,
                                    forceSave: forceSave,
                                    requiresDurableFile: forceSave || requiresDurableFile
                                )
                                if added.reusesLocalFile {
                                    locallyReusedFileIds.insert(newItem.id)
                                }
                                fileWrite = added.write
                            }
                            if await itemControllable.shouldDeferGameModeFolderImport(newItem, writesGameMemory: policy.writesGameMemory) {
                                deferredFolderItems.append((newItem, newItem.id))
                            } else {
                                if await applyImportedItem(newItem, id: newItem.id, policy: policy, importModel: importModel, locallyReusedFileIds: locallyReusedFileIds) {
                                    folderRepairIds.insert(newItem.id)
                                }
                            }
                            if let fileWrite {
                                await settleImportedFile(fileWrite, itemId: newItem.id, policy: policy, importModel: importModel)
                            }
                            importedIds.insert(newItem.id)
                        } catch {
                            // A single undecodable item is skipped (and reported); cancelling stops the import.
                            if error is CancellationError { throw error }
                            await recordFailedItem(importModel)
                            await logImportFailure(error)
                        }
                    default:
                        throw ItemDataImportableError.unsupportedDataType
                    }
                } catch {
                    // Framing errors (a truncated block, an unknown token) mean the rest of the
                    // stream cannot be trusted, so they fail the import instead of being logged
                    // while the import reports success. See CODE_AUDIT_15 §5.7.
                    await logImportFailure(error)
                    throw error
                }
            }

            try Task.checkCancellation()
            if let peerPolicy, !peerFolderItems.isEmpty {
                let admitted = await admitPeerFolders(peerFolderItems, policy: peerPolicy)
                for folder in admitted {
                    deferredFolderItems.append(folder)
                    importedIds.insert(folder.id)
                }
                await recordProcessedItems(importModel, count: max(0, peerFolderItems.count - admitted.count))
            }
            for deferredFolderItem in deferredFolderItems {
                let applied = await applyImportedItem(
                    deferredFolderItem.item,
                    id: deferredFolderItem.id,
                    policy: policy,
                    importModel: importModel,
                    locallyReusedFileIds: locallyReusedFileIds
                )
                if applied {
                    folderRepairIds.insert(deferredFolderItem.id)
                }
            }
            await repairFolders(folderRepairIds)
        } catch {
            // The items applied so far stay; repair their folder links before failing, or a
            // child whose folder comes later in the stream stays orphaned until the user runs
            // Validate. See CODE_AUDIT_Folder §3.3.
            await repairFolders(folderRepairIds)
            if policy.repairsImportedItems {
                await repairImportedItems(importedIds)
            }
            throw error
        }

        if policy.mode == .manual {
            // Collect local items absent from the import stream as deletion candidates
            let module = itemControllable.config.module
            let ic = itemControllable
            let allLocalIds = await localItemIds(of: ic)
            for deletedId in allLocalIds.subtracting(importedIds) {
                await appendDeletionReviewItem(deletedId: deletedId, module: module, itemController: ic, importModel: importModel)
            }
        } else if policy.repairsImportedItems {
            await repairImportedItems(importedIds)
        }

        try await finalImport(
            from: inputStream,
            forceSave: forceSave,
            importModel: importModel,
            gameMemoryOnly: gameMemoryOnly
        )
    }

    // MARK: - Import Lifecycle

    /// The error's domain and code are public, its description (which can name the user's file)
    /// is private. It was logged in the public title. See CODE_AUDIT_Folder §6.5.
    func logImportFailure(_ error: any Error) async {
        let token = await self.token()
        Logger.importController.error("Import error \(token, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
    }

    func logImport(title: String, count: Int, importModel: ItemDataImportModel) async {
        let token = await self.token()
        let (importedItems, totalItems) = await importProgress(importModel)
        Logger.importController.info("\(title, privacy: .public) \(token, privacy: .public) currentItems \(count), importedItems \(importedItems), total: \(totalItems)")
    }

    @MainActor
    private func importProgress(_ importModel: ItemDataImportModel) -> (importedItems: Int, totalItems: Int) {
        (importModel.importedItems, importModel.totalImportingItems)
    }

    @MainActor
    private func localItemIds(of itemController: any ItemControllable) -> Set<UUID> {
        Set(itemController.itemDataModel.items)
    }

    @MainActor
    private func appendDeletionReviewItem(
        deletedId: UUID,
        module: NetworkModules,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        guard let deletedIA: any ItemDataAccessible = itemController.itemSync(for: deletedId) else { return }
        let reviewItem = SingleReviewItem(existing: deletedIA, imported: deletedIA, merged: deletedIA)
        let itemModel = SingleItemImportModel.from(item: reviewItem)
        let reviewItemModel = ImportReviewItemModel(
            id: deletedId,
            kind: .different,
            itemModel: itemModel,
            isDeletion: true
        )
        importModel.pendingModules[module, default: []].append(reviewItemModel)
    }
}
private extension ImportControllable {
    @MainActor
    func token() async -> Int {
        itemControllable.config.module.rawValue
    }

    func performImport(from url: URL, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        // A coordinated read first: a picked iCloud file that is still a placeholder downloads on
        // the file-coordination queue here, instead of while a cooperative-pool thread blocks in
        // `InputStream.read`. See CODE_AUDIT_Folder §3.19.
        guard try await FileManager.default.fileExists(coordinatingAccessAt: url).exists else {
            throw ItemDataImportableError.openError
        }
        guard let inputStream = InputStream(url: url) else { throw ItemDataImportableError.openError }

        inputStream.open()
        defer { inputStream.close() }

        let fileHeader = try inputStream.readHeader()
        guard fileHeader.token == ExportDataToken.counter.rawValue &&
                fileHeader.version == ExportDataToken.version_2024.rawValue else { throw ItemDataImportableError.notEnoughData }

        await beginImport(importModel, totalItems: fileHeader.counter)

        do {
            try await self.importStream(from: inputStream, forceSave: true, importModel: importModel, gameMemoryOnly: gameMemoryOnly)
            await finishImport(importModel)
        } catch {
            await stopImport(importModel)
            throw Task.isCancelled ? ItemDataImportableError.cancel : error
        }
    }

    @MainActor
    private func beginImport(_ importModel: ItemDataImportModel, totalItems: Int) {
        importModel.importedItems = 0
        importModel.failedItems = 0
        importModel.totalImportingItems = totalItems
        importModel.isImportRunning = true
    }

    @MainActor
    private func finishImport(_ importModel: ItemDataImportModel) {
        importModel.isImportRunning = false
        if importModel.importMode == .manual { importModel.finalizeReview() }
    }

    @MainActor
    private func stopImport(_ importModel: ItemDataImportModel) {
        importModel.isImportRunning = false
    }

    /// Counts items the import finished without applying them, so the progress reaches its total.
    @MainActor
    private func recordProcessedItems(_ importModel: ItemDataImportModel, count: Int) {
        importModel.importedItems += count
    }

    @MainActor
    private func recordFailedItem(_ importModel: ItemDataImportModel) {
        importModel.failedItems += 1
        // A failed item is processed too, or the progress never reaches the total.
        // See CODE_AUDIT_26 §5.52.
        importModel.importedItems += 1
    }

    // MARK: - Item Application

    /// Replaces the file description of a decoded item by its sanitised form (no `..` segments,
    /// private storage, checked remote hosts). See CODE_AUDIT_15 §5.1.
    @MainActor
    private func sanitizeImportedFileUrl(of item: any ItemDataAccessible, allowsPrivateRemoteHosts: Bool) {
        var item = item
        if let importedFileUrl = item.fileUrl {
            item.fileUrl = importedFileUrl.sanitizedForImport(allowsPrivateRemoteHosts: allowsPrivateRemoteHosts)
        }
    }

    /// Makes a freshly decoded item safe to apply: its file description came out of the imported
    /// bytes and is never resolved as-is (CODE_AUDIT_15 §5.1), and a peer's package may only
    /// write what its `PeerImportPolicy` admits (§5.2). Returns `false` when the item must be
    /// skipped.
    @MainActor
    private func prepareDecodedItem(_ item: any ItemDataAccessible, allowsPrivateRemoteHosts: Bool, peerPolicy: PeerImportPolicy?) -> Bool {
        sanitizeImportedFileUrl(of: item, allowsPrivateRemoteHosts: allowsPrivateRemoteHosts)
        guard let peerPolicy else { return true }
        let existsLocally = itemControllable.itemSync(for: item.id, noGame: true) != nil
        guard peerPolicy.admit(itemId: item.id, existsLocally: existsLocally) else {
            Logger.importController.warning("Import skipped a peer item that is not the sender's own module=\(itemControllable.config.module.rawValue, privacy: .public) item=\(item.id, privacy: .public)")
            return false
        }
        return true
    }

    /// The folders of a peer package that may be written, each reduced to the entries of items
    /// the peer introduced. See `PeerImportPolicy.admitFolders`.
    @MainActor
    private func admitPeerFolders(_ folders: [ModelType], policy: PeerImportPolicy) -> [(item: ModelType, id: UUID)] {
        let itemController = itemControllable
        // Each folder is described once (a library lookup); the admitted ones are then found
        // by id instead of by describing every folder again. See CODE_AUDIT_24 §7.2.
        let pairs: [(item: ModelType, folder: PeerImportPolicy.Folder)] = folders.compactMap { item in
            itemController.peerFolder(item).map { (item, $0) }
        }
        let keptChildIds = policy.admitFolders(pairs.map(\.folder))
        var itemsById: [UUID: ModelType] = [:]
        for pair in pairs where itemsById[pair.folder.id] == nil {
            itemsById[pair.folder.id] = pair.item
        }
        return pairs.compactMap { pair in
            guard let kept = keptChildIds[pair.folder.id],
                  let item = itemsById[pair.folder.id]
            else { return nil }
            return (itemController.folder(item, keepingChildIds: { kept.contains($0) }), pair.folder.id)
        }
    }

    /// Captures, once per module stream, where its items go. Reading `isGameMode` separately at
    /// every step let a game that ended mid-package send later items of the same package to the
    /// permanent library. See CODE_AUDIT_Folder §3.4.
    @MainActor
    func applyPolicy(importModel: ItemDataImportModel, forceSave: Bool, gameMemoryOnly: Bool) -> ImportApplyPolicy {
        ImportApplyPolicy(
            mode: importModel.importMode,
            forceSave: forceSave,
            gameMemoryOnly: gameMemoryOnly,
            writesGameMemory: !forceSave && itemControllable.itemDataModel.isGameMode,
            isUntrustedSource: importModel.isUntrustedSource
        )
    }

    /// Normalises, merges and writes one decoded item in a single main-actor step, so no sync or
    /// user edit can land between the merge and the write and be overwritten by the stale merge
    /// result. See CODE_AUDIT_Folder §3.4. Returns whether the item was written to a module list
    /// whose folders `repairFolders` must then check; the caller repairs once per batch.
    /// See CODE_AUDIT_Folder §7.3.
    @discardableResult @MainActor
    func applyImportedItem(_ importedItem: ModelType, id: UUID, policy: ImportApplyPolicy, importModel: ItemDataImportModel, locallyReusedFileIds: Set<UUID>) -> Bool {
        let itemController = itemControllable
        // A memory-only game delivery whose game has ended since the package started has no
        // game memory left to go to, and must not fall through to the library.
        guard !policy.writesGameMemory || itemController.itemDataModel.isGameMode else {
            Logger.importController.info("Import dropped an item of a game package that arrived after the game ended module=\(itemController.config.module.rawValue, privacy: .public)")
            importModel.importedItems += 1
            return false
        }
        let normalizedImportedItem = itemController.normalizedImportedItem(from: importedItem)
        guard let importableItem = itemController.gameModeImportedItem(from: normalizedImportedItem, writesGameMemory: policy.writesGameMemory, locallyReusedFileIds: locallyReusedFileIds) else {
            importModel.importedItems += 1
            return false
        }

        // A saved-game load never touches the permanent library — write straight into this
        // module's game memory regardless of merge/overwrite mode or isGameMode.
        // `replaceForGame(policy: .memoryOnly)` only fills the game-shadow dictionary
        // (`gameItemData`); nothing considers the item "in the running game" — `gameItems`
        // stays the authority for that (see `ItemGameModel.currentItemId`/`.items`) — until it's
        // in that id list too, so add it there ourselves.
        guard !policy.gameMemoryOnly else {
            replaceForGameAndCount(importableItem, id: id, itemController: itemController, importModel: importModel)
            importModel.recordApplied(id, module: itemController.config.module)
            return false
        }

        let writePolicy: GameMutationPolicy = policy.writesGameMemory ? .memoryOnly : .persist
        var needsFolderRepair = false
        switch policy.mode {
        case .merge:
            var finalItem = itemController.mergeSync(with: importableItem, forceMerge: !policy.writesGameMemory)
            if !policy.writesGameMemory {
                let merged = finalItem
                finalItem = itemController.restoringTrashedItem(merged: merged, imported: importableItem)
                if let restored = finalItem as? any ItemDataAccessible, !restored.isHidden,
                   itemController.itemSync(for: id, noGame: true)?.isHidden == true {
                    // Trashing gave the tags back; restoring takes them again.
                    editControllable.tagController.add(tags: restored.tags, module: itemController.config.module)
                }
            }
            if let finalItem {
                itemController.replaceImportedModel(model: finalItem, isInsert: true, policy: writePolicy)
                needsFolderRepair = true
                importModel.recordApplied(id, module: itemController.config.module)
            }

        case .overwrite:
            let finalItem = policy.writesGameMemory ? importableItem : itemController.keepingLocalFolderChildren(importableItem)
            itemController.replaceImportedModel(model: finalItem, isInsert: true, policy: writePolicy)
            needsFolderRepair = true
            importModel.recordApplied(id, module: itemController.config.module)

        case .manual:
            var merged = itemController.mergeSync(with: importableItem, forceMerge: !policy.writesGameMemory)
            if !policy.writesGameMemory {
                // The restore rule of the merge branch: a local item in the trash that the
                // backup has is offered restored. Without it an otherwise equal item was
                // skipped as unchanged, a different one kept its trashed state by default, and
                // both were purged at the next launch. Opening a backup file starts in manual
                // mode. See CODE_AUDIT_Folder §5.20, CODE_AUDIT_21 §5.30.
                merged = itemController.restoringTrashedItem(merged: merged, imported: importableItem)
            }
            recordManualReview(importableItem: importableItem, merged: merged as? any ItemDataAccessible, id: id, itemController: itemController, importModel: importModel)
        }

        importModel.importedItems += 1
        return needsFolderRepair
    }

    @MainActor
    func repairFolders(_ itemIds: Set<UUID>) {
        guard !itemIds.isEmpty else { return }
        editControllable.repairFolders(itemIds: itemIds)
    }

    /// Cleans up after a file the import wrote for `itemId`. A library import keeps the file the
    /// item references now and removes the other; files of game-memory items are removed at game
    /// end, and files of a manual review once the review is applied or cancelled.
    /// See CODE_AUDIT_Folder §5.2, §5.26.
    @MainActor
    func settleImportedFile(_ fileWrite: ImportedFileWrite, itemId: UUID, policy: ImportApplyPolicy, importModel: ItemDataImportModel) async {
        if policy.gameMemoryOnly || policy.writesGameMemory {
            itemControllable.fileUrlDataController?.model.gameMemoryFiles.append(fileWrite.written)
        } else if policy.mode == .manual {
            importModel.reviewFileWrites.append((itemControllable.config.module, itemId, fileWrite))
        } else {
            await itemControllable.settleImportedFile(fileWrite, itemId: itemId)
        }
    }

    /// Runs the post-import folder and orphan repair for `importedIds`. In an unstructured task:
    /// the repair stops at `Task.isCancelled`, and after a cancelled import it must still run
    /// for the items already applied. See CODE_AUDIT_Folder §3.3.
    func repairImportedItems(_ importedIds: Set<UUID>) async {
        guard !importedIds.isEmpty else { return }
        let itemController = itemControllable
        let editController = editControllable
        await Task { @MainActor in
            let repair = ConvertController(itemController: itemController, editController: editController)
            await repair.repairImportedItems(reportModel: ValidateRepairModel(), importedIds: importedIds)
        }.value
    }

    @MainActor
    private func replaceForGameAndCount(
        _ importableItem: ModelType,
        id: UUID,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        itemController.replaceForGame(model: importableItem, isInsert: true, policy: .memoryOnly)
        if !itemController.itemDataModel.isGameMode {
            itemController.itemDataModel.isSavedGameStaged = true
        }
        if !itemController.itemDataModel.gameItems.contains(id) {
            itemController.itemDataModel.gameItems.insert(id, at: 0)
        }
        importModel.importedItems += 1
    }

    @MainActor
    private func recordManualReview(
        importableItem: ModelType,
        merged: (any ItemDataAccessible)?,
        id: UUID,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        guard let imported = importableItem as? any ItemDataAccessible else { return }
        // A copy, not the live item: applying the review compares it with the library item to
        // detect a change made while the review sheet was open. See CODE_AUDIT_Folder §3.17.
        let existing: (any ItemDataAccessible)? = itemController.itemSync(for: id, noGame: true)?.copy()
        let module = itemController.config.module

        if existing != nil && merged == nil {
            logManualReviewUnchangedSkipped(module: module, id: id, imported: imported)
            return
        }

        let kind: ImportReviewItemModel.ChangeKind = existing == nil ? .added : .different
        let reviewItem = SingleReviewItem(existing: existing, imported: imported, merged: merged ?? imported)
        let itemModel = SingleItemImportModel.from(item: reviewItem)
        if kind == .different {
            logManualReviewDifference(
                module: module,
                id: id,
                existing: existing,
                imported: imported,
                itemModel: itemModel
            )
        }
        let reviewItemModel = ImportReviewItemModel(
            id: id,
            kind: kind,
            itemModel: itemModel
        )
        importModel.pendingModules[module, default: []].append(reviewItemModel)
    }

    // MARK: - File Handling

    func skip(itemCount: Int, from inputStream: InputStream, importModel: ItemDataImportModel) async throws {
        await logImport(title: "skip", count: itemCount, importModel: importModel)
        var counter = 0
        while counter < itemCount {
            try Task.checkCancellation()
            guard inputStream.hasBytesAvailable else {
                throw ItemDataImportableError.notEnoughData
            }

            let (dataSize, dataToken) = try inputStream.readItemHeader()
            let _ = try inputStream.readData(size: dataSize)
            if dataToken == ExportDataToken.item.rawValue {
                counter += 1
            }
        }
    }

    /// Stores the imported bytes of `item`'s file. Returns whether a game delivery reuses the
    /// local file, and the file it wrote (if any) for `settleImportedFile` to clean up after.
    /// - Parameter requiresDurableFile: The file must reach disk or the import of this item
    ///   fails: a library import, or a game delivery that is stored. See CODE_AUDIT_21 §5.14.
    @MainActor func addFile(data: Data, to item: any ItemDataAccessible, forceSave: Bool, requiresDurableFile: Bool) async throws -> (reusesLocalFile: Bool, write: ImportedFileWrite?) {
        guard let fileUrlDataController, var fileUrl = item.fileUrl else { return (false, nil) }
        var item = item
        let module = itemControllable.config.module.rawValue
        // Hashed once, off the main actor; `resetData` below reuses it. See CODE_AUDIT_Folder §7.1.
        let importedHash = await FileUrl.computeContentHash(of: data)
        let localFileUrl = itemControllable.itemSync(for: item.id, noGame: true)?.fileUrl

        // Reuse the existing file when the binary is unchanged — do not write the same file again
        if let existingFileUrl = await reusableExistingFileUrl(for: item.id, importedHash: importedHash, forceSave: forceSave) {
            // A game delivery of a file that is on iCloud Drive but not downloaded here: the
            // iCloud file is left alone (it downloads on its own, `hasDownloadedData` asked for
            // it), and the controller holds the peer's bytes so the game can show them now.
            // Dropping them left the player with a placeholder it could not read.
            var keepsBytesInMemory = false
            if forceSave == false {
                keepsBytesInMemory = await !fileUrlDataController.hasDownloadedData(for: existingFileUrl)
            }
            if keepsBytesInMemory {
                fileUrlDataController.holdPeerData(data, for: existingFileUrl)
            }
            Logger.importController.debug("Import addFile reuses existing file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(existingFileUrl.fileId, privacy: .public) hash=\(importedHash, privacy: .public) forceSave=\(forceSave, privacy: .public) inMemory=\(keepsBytesInMemory, privacy: .public)")
            item.fileUrl = existingFileUrl
            if forceSave == false, let localItem = itemControllable.itemSync(for: item.id, noGame: true) {
                item.parentId = localItem.parentId
            }
            return (forceSave == false, nil)
        }

        if let localFileUrl {
            Logger.importController.warning("Import addFile rewrites existing file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) forceSave=\(forceSave, privacy: .public) localHash=\(localFileUrl.contentHash ?? "nil", privacy: .public) importedHash=\(importedHash, privacy: .public) localUrl=\(localFileUrl.rawUrl.absoluteString, privacy: .private) importedUrl=\(fileUrl.rawUrl.absoluteString, privacy: .private)")
        } else {
            Logger.importController.debug("Import addFile writes new file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) hash=\(importedHash, privacy: .public) forceSave=\(forceSave, privacy: .public)")
        }

        // Never over another item's file, or over a newer local version of this one: a taken
        // path gets the next free name. See CODE_AUDIT_Folder §5.2.
        fileUrl = try await fileUrlDataController.importDestination(
            for: fileUrl,
            contentHash: importedHash,
            referencedFileUrls: itemControllable.libraryFileUrls()
        )
        fileUrl.resetData(data, contentHash: importedHash)
        do {
            // A library import must not count an item whose file never reached disk; the
            // in-memory fallback is lost at relaunch. Game deliveries keep it.
            // See CODE_AUDIT_Folder §5.26.
            let updated = try await fileUrlDataController.createNewFileUrl(fileId: fileUrl.fileId, unconvertedFileUrl: fileUrl, pathExtension: fileUrl.rawUrl.pathExtension, requireDurableStorage: requiresDurableFile)
            Logger.importController.debug("Import addFile stored imported file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) storedUrl=\((updated ?? fileUrl).rawUrl.absoluteString, privacy: .private) storedHash=\((updated ?? fileUrl).contentHash ?? "nil", privacy: .public)")
            let stored = updated ?? fileUrl
            // The write fell back to memory (tvOS cannot store files): item replacement and
            // sync merges drop bytes that sit on the item, so they are held by file id, which
            // every reader (`loadData`, `url(for:)`, `hasDownloadedData`) consults.
            if stored.hasUnconvertedData, stored.location == .newCloud {
                fileUrlDataController.holdPeerData(data, for: stored)
            }
            await itemControllable.reset(fileUrl: stored, item: &item)
            return (false, ImportedFileWrite(written: stored, previous: localFileUrl))
        } catch {
            guard !requiresDurableFile else { throw error }
            Logger.importController.error("Cannot store the delivered file \(module, privacy: .public), keeping it in memory for the game")
            fileUrlDataController.holdPeerData(data, for: fileUrl)
            await itemControllable.reset(fileUrl: fileUrl, item: &item)
            return (false, nil)
        }
    }

    /// The existing item's local file URL when the imported bytes are unchanged.
    /// In game mode (`forceSave == false`) this deliberately avoids writing a
    /// content-hash-only change back into the game item observed by the UI.
    @MainActor func reusableExistingFileUrl(for itemId: UUID, importedHash: String, forceSave: Bool) async -> FileUrl? {
        guard let existing = itemControllable.itemSync(for: itemId, noGame: true), var existingFileUrl = existing.fileUrl else { return nil }
        if let contentHash = existingFileUrl.contentHash {
            guard contentHash == importedHash else { return nil }
            // A matching hash is not enough: a metadata-only import carries the
            // hash without the binary. Only reuse when the file really exists.
            guard await fileUrlDataController?.hasLocalData(for: existingFileUrl) == true else { return nil }
            return existingFileUrl
        }
        // Without a hash the file must be read to compare. A game delivery must not wait on the
        // iCloud download of a file that is not here yet: it reuses the reference and keeps the
        // peer's bytes in memory (see `addFile`); nothing is written in game mode.
        if forceSave == false, await fileUrlDataController?.hasLocalData(for: existingFileUrl) == true,
           await fileUrlDataController?.hasDownloadedData(for: existingFileUrl) == false {
            return existingFileUrl
        }
        // Streamed from disk off the main actor instead of loading the whole file to hash it.
        // See CODE_AUDIT_Folder §7.1.
        guard let existingHash = try? await fileUrlDataController?.contentHash(for: existingFileUrl),
              existingHash == importedHash else { return nil }
        guard forceSave else { return existingFileUrl }

        existingFileUrl.resetContentHash(existingHash)
        persist(fileUrl: existingFileUrl, itemId: itemId)
        return existingFileUrl
    }

    @MainActor
    func persist(fileUrl: FileUrl, itemId: UUID) {
        guard var copy = itemControllable.itemSync(for: itemId, noGame: true)?.copy() else { return }
        copy.fileUrl = fileUrl
        itemControllable.replace(model: copy, isInsert: false, forceSave: true)
    }
}

private extension ItemControllable {
    /// Whether the imported item is a folder.
    @MainActor
    func isFolderImport(_ item: ModelType) -> Bool {
        (item as? Model)?.category == .folder
    }

    @MainActor
    func peerFolder(_ item: ModelType) -> PeerImportPolicy.Folder? {
        guard let folder = item as? Model else { return nil }
        return PeerImportPolicy.Folder(
            id: folder.id,
            childIds: folder.entries.map(\.childId),
            existsLocally: itemSync(for: folder.id, noGame: true) != nil
        )
    }

    /// A copy of the folder with only the entries whose child passes `keep`. The one place a
    /// folder's entries are filtered by child id, for peer admission and game-mode import alike.
    @MainActor
    func folder(_ folder: Model, keepingChildIds keep: (UUID) -> Bool) -> Model {
        let reduced = folder.copy()
        reduced.entries.removeAll { !keep($0.childId) }
        return reduced
    }

    /// The same for a decoded item of unknown type: anything but a folder is returned as is.
    @MainActor
    func folder(_ item: ModelType, keepingChildIds keep: (UUID) -> Bool) -> ModelType {
        guard let folder = item as? Model else { return item }
        return self.folder(folder, keepingChildIds: keep)
    }

    @MainActor
    func shouldDeferGameModeFolderImport(_ item: ModelType, writesGameMemory: Bool) -> Bool {
        writesGameMemory && isFolderImport(item)
    }

    @MainActor
    func normalizedImportedItem(from item: ModelType) -> ModelType {
        guard var imported = (item as? Model)?.copy() else { return item }
        normalizeImportedItemForMerge(in: &imported)
        return imported
    }

    @MainActor
    func gameModeImportedItem(from item: ModelType, writesGameMemory: Bool, locallyReusedFileIds: Set<UUID>) -> ModelType? {
        guard writesGameMemory, var imported = (item as? Model)?.copy() else { return item }

        if locallyReusedFileIds.contains(imported.id), let localItem = itemSync(for: imported.id, noGame: true) {
            imported.parentId = localItem.parentId
            return imported
        }

        guard imported.category == .folder, !locallyReusedFileIds.isEmpty else { return imported }
        let reduced = folder(imported, keepingChildIds: { !locallyReusedFileIds.contains($0) })
        return reduced.entries.isEmpty ? nil : reduced
    }

    @MainActor
    func normalizeImportedItemForMerge(in item: inout Model) {
        ImportItemRepair.normalizeLegacyCategory(in: &item)

        if config.module == .photo && item.category == .entry {
            item.entries = []
        }
    }
}
