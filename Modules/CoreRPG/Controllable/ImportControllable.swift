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
            await repairFolders(folderRepairIds, forceSave: !policy.writesGameMemory)
        } catch {
            // The items applied so far stay; repair their folder links before failing, or a
            // child whose folder comes later in the stream stays orphaned until the user runs
            // Validate. See CODE_AUDIT_Folder §3.3.
            await repairFolders(folderRepairIds, forceSave: !policy.writesGameMemory)
            if policy.repairsImportedItems {
                await removeStaleGroups(importModel: importModel)
                await repairImportedItems(importedIds, forceSave: !policy.writesGameMemory)
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
            await removeStaleGroups(importModel: importModel)
            await repairImportedItems(importedIds, forceSave: !policy.writesGameMemory)
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

}

// Internal, not private: `ImportControllable+Apply.swift` uses these too. See CODE_AUDIT_29 §9.9.
extension ItemControllable {
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
