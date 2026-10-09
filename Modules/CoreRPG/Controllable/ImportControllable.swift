// @copyright André Trettin

import Foundation
import os.log
import Observation

// MARK: - Import State

public enum ImportMode: Hashable, Sendable, CaseIterable {
    case merge, overwrite, manual
}

/// A file an import wrote for an item, and the file that item had before.
/// See CODE_AUDIT_Folder §5.26.
struct ImportedFileWrite: Sendable {
    let written: FileUrl
    let previous: FileUrl?
}

/// Where the items of one module stream go, decided once when the stream starts.
/// See CODE_AUDIT_Folder §3.4.
struct ImportApplyPolicy: Sendable {
    let mode: ImportMode
    let forceSave: Bool
    /// A saved-game load: items go to game memory only, whatever the mode.
    let gameMemoryOnly: Bool
    /// A game delivery that started during a running game: items go to game memory only.
    let writesGameMemory: Bool
    let isUntrustedSource: Bool

    /// The post-import folder repair runs for everything but manual review and saved-game loads.
    var repairsImportedItems: Bool {
        mode != .manual && !gameMemoryOnly
    }
}

/// What a game peer's package may write into this device's library. A peer is only trusted
/// with its own data, so an item is admitted when it is the peer's primary item, was
/// introduced by this same peer before, or does not exist here yet — a package can never
/// overwrite another item the device already owns. The item count is capped as well.
/// See CODE_AUDIT_15 §5.2.
///
/// Known gaps, accepted by design and never to be fixed (CODE_AUDIT_Folder §6.2): ids are not
/// keyed by module, the cap is per package rather than per session, and a new folder's entries
/// pointing at existing items are stripped only in game memory. Each needs a deliberately crafted
/// package, and only players the game master knows can connect: SharePlay runs among FaceTime
/// friends, a local-network game is played by people at the same table, and a public
/// local-network game needs its join code.
@MainActor
public final class PeerImportPolicy {
    public static let defaultMaximumItems = 256

    public let primaryItemId: UUID
    public let maximumItems: Int
    public private(set) var ownedItemIds: Set<UUID>
    public private(set) var admittedItemIds: Set<UUID> = []
    public private(set) var rejectedItemCount = 0

    public init(primaryItemId: UUID, ownedItemIds: Set<UUID> = [], maximumItems: Int = PeerImportPolicy.defaultMaximumItems) {
        self.primaryItemId = primaryItemId
        self.ownedItemIds = ownedItemIds
        self.maximumItems = maximumItems
    }

    /// Ids the peer has introduced so far, to hand back to the caller for the next package.
    public var introducedItemIds: Set<UUID> { ownedItemIds.union(admittedItemIds) }

    /// INTENDED BEHAVIOR — do not "fix" (CODE_AUDIT_17 §6.1, decided won't fix): the peer's
    /// primary item (its own Character) is admitted even when it already exists locally, so a
    /// player can overwrite that Character on the master to update its values. Reaching this
    /// path needs a connected peer: LAN is PIN-protected, unknown connections are only accepted
    /// if the game master allows them, and SharePlay is a real FaceTime call.
    func admit(itemId: UUID, existsLocally: Bool) -> Bool {
        let isAllowed = itemId == primaryItemId
            || ownedItemIds.contains(itemId)
            || !existsLocally
        guard isAllowed, admittedItemIds.count < maximumItems || admittedItemIds.contains(itemId) else {
            rejectedItemCount += 1
            return false
        }
        admittedItemIds.insert(itemId)
        return true
    }
}

@MainActor @Observable
public final class ItemDataImportModel {
    public init() {}

    /// Lets a caller set the initial mode atomically with construction — calling an
    /// isolated initializer with `await` works the same as calling an isolated method;
    /// only a bare property *write* on an already-existing instance needs its own
    /// isolated function (see CODE_AUDIT §3.2).
    public convenience init(importMode: ImportMode) {
        self.init()
        self.importMode = importMode
    }

    /// Set for data received from a game peer instead of a file the user picked: the sender
    /// controls every field of it, so imported `FileUrl`s get the strictest sanitising.
    /// See CODE_AUDIT_15 §5.1 / §6.3.
    public convenience init(importMode: ImportMode, isUntrustedSource: Bool) {
        self.init(importMode: importMode)
        self.isUntrustedSource = isUntrustedSource
    }

    public private(set) var isUntrustedSource: Bool = false

    /// Limits what a peer's package may write; see `PeerImportPolicy`.
    public private(set) var peerPolicy: PeerImportPolicy?

    public convenience init(importMode: ImportMode, peerPolicy: PeerImportPolicy?) {
        self.init(importMode: importMode, isUntrustedSource: true)
        self.peerPolicy = peerPolicy
    }

    /// Set for a game delivery that will be stored in the library: its files must reach disk,
    /// the in-memory fallback of a game-only delivery is not enough. See CODE_AUDIT_21 §5.14.
    public private(set) var requiresDurableFiles = false

    public convenience init(importMode: ImportMode, peerPolicy: PeerImportPolicy?, requiresDurableFiles: Bool) {
        self.init(importMode: importMode, peerPolicy: peerPolicy)
        self.requiresDurableFiles = requiresDurableFiles
    }

    public var importedItems: Int = 0
    /// Items of the import that could not be decoded or applied. Shown after the import so a
    /// partly failed file no longer reads as a clean success. See CODE_AUDIT_15 §5.7.
    public var failedItems: Int = 0
    public var totalImportingItems: Int = 0
    public var isImportRunning: Bool = false
    public var importMode: ImportMode = .merge
    public var isReviewReady: Bool = false
    var reviewModel: ImportReviewModel? = nil

    var pendingModules: [NetworkModules: [ImportReviewItemModel]] = [:]

    /// The ids each module's import actually wrote (merged, overwritten or loaded into game
    /// memory); items an unchanged merge skipped are not included. Lets a game delivery see
    /// what a package changed without comparing object identities. See CODE_AUDIT_Folder §5.10,
    /// §5.22.
    public private(set) var appliedItemIds: [NetworkModules: Set<UUID>] = [:]

    /// Files a manual-review import wrote while parsing; cleaned up once the review is applied
    /// or cancelled. See CODE_AUDIT_Folder §5.2.
    var reviewFileWrites: [(module: NetworkModules, itemId: UUID, write: ImportedFileWrite)] = []

    func recordApplied(_ itemId: UUID, module: NetworkModules) {
        appliedItemIds[module, default: []].insert(itemId)
    }
    var isFinalizingImport: Bool {
        isImportRunning
            && totalImportingItems > 0
            && importedItems >= totalImportingItems
    }

    func finalizeReview() {
        let modules = pendingModules
            .map { ImportReviewModule(id: $0.key, reviewItems: $0.value) }
            .sorted { $0.name < $1.name }
        reviewModel = modules.isEmpty ? nil : ImportReviewModel(modules: modules)
        isReviewReady = true
    }
}

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
                            guard await prepareDecodedItem(newItem, allowsPrivateRemoteHosts: !policy.isUntrustedSource, peerPolicy: peerPolicy) else {
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

/// The import log, to ask whether info-level messages are recorded before building one that is
/// expensive to build. See CODE_AUDIT_21 §7.2.
private let importReviewLog = OSLog(subsystem: Logger.subsystem, category: "ImportController")

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

    @MainActor
    private func recordFailedItem(_ importModel: ItemDataImportModel) {
        importModel.failedItems += 1
    }

    // MARK: - Item Application

    /// Makes a freshly decoded item safe to apply: its file description came out of the imported
    /// bytes and is never resolved as-is (CODE_AUDIT_15 §5.1), and a peer's package may only
    /// write what its `PeerImportPolicy` admits (§5.2). Returns `false` when the item must be
    /// skipped.
    @MainActor
    private func prepareDecodedItem(_ item: any ItemDataAccessible, allowsPrivateRemoteHosts: Bool, peerPolicy: PeerImportPolicy?) -> Bool {
        var item = item
        if let importedFileUrl = item.fileUrl {
            item.fileUrl = importedFileUrl.sanitizedForImport(allowsPrivateRemoteHosts: allowsPrivateRemoteHosts)
        }
        guard let peerPolicy else { return true }
        let existsLocally = itemControllable.itemSync(for: item.id, noGame: true) != nil
        guard peerPolicy.admit(itemId: item.id, existsLocally: existsLocally) else {
            Logger.importController.warning("Import skipped a peer item that is not the sender's own module=\(itemControllable.config.module.rawValue, privacy: .public) item=\(item.id, privacy: .public)")
            return false
        }
        return true
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
                if let restored = finalItem as? any ItemDataAccessible, restored.displayState != DisplayStateMask.totalHidden.rawValue,
                   itemController.itemSync(for: id, noGame: true)?.displayState == DisplayStateMask.totalHidden.rawValue {
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

    // MARK: - Manual Review Diffing

    @MainActor
    func logManualReviewDifference(
        module: NetworkModules,
        id: UUID,
        existing: (any ItemDataAccessible)?,
        imported: any ItemDataAccessible,
        itemModel: SingleItemImportModel
    ) {
        guard let existing else {
            Logger.importController.info("Manual import review added \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)'")
            return
        }

        // The summary below compares every property and entry again, only to be logged at the
        // info level. See CODE_AUDIT_21 §7.2.
        guard importReviewLog.isEnabled(type: .info) else { return }
        let reviewDifferences = reviewPropertyDifferences(in: itemModel) + reviewEntryDifferences(in: itemModel)
        let commonDifferences = commonItemDifferences(existing: existing, imported: imported)
        let reviewSummary = reviewDifferences.importLogSummary
        let commonSummary = commonDifferences.importLogSummary

        if reviewDifferences.isEmpty && commonDifferences.isEmpty {
            Logger.importController.warning("Manual import review different \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' but review/common fields match. model.isSame returned false; likely CRDT update metadata or module-specific fields not exposed in reviewProperties.")
        } else {
            // User-authored sheet content — imported item/entry field values — defaults to
            // `.private` here (unlike the enum/identifier fields alongside it), matching the
            // project's logging privacy convention. This is the highest-content-volume site of
            // that gap: unredacted excerpts of imported character sheets, adventure notes, or
            // campaign content previously persisted in plaintext system logs during ordinary
            // (non-DEBUG-gated) import review. See CODE_AUDIT §6.4.
            Logger.importController.info("Manual import review different \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' reviewRows=\(reviewSummary, privacy: .private) commonFields=\(commonSummary, privacy: .private)")
        }
    }

    @MainActor
    func logManualReviewUnchangedSkipped(module: NetworkModules, id: UUID, imported: any ItemDataAccessible) {
        Logger.importController.info("Manual import review unchanged skipped \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' because merge returned nil (model.isSame == true).")
    }

    @MainActor
    func reviewPropertyDifferences(in itemModel: SingleItemImportModel) -> [String] {
        itemModel.properties.compactMap { property in
            guard itemModel.isChanged(prop: property) else { return nil }
            return "property '\(property.displayName)': existing='\((itemModel.existingValue(for: property) ?? "nil").importLogPreview)' imported='\((itemModel.importedValue(for: property) ?? "nil").importLogPreview)' merged='\((itemModel.mergedValue(for: property) ?? "nil").importLogPreview)'"
        }
    }

    @MainActor
    func reviewEntryDifferences(in itemModel: SingleItemImportModel) -> [String] {
        itemModel.entries.flatMap { entryModel in
            let entryLabel = "\(entryModel.name.importLogPreview) (\(entryModel.id.uuidString))"

            if entryModel.entry.existing == nil {
                return ["entry added '\(entryLabel)'"]
            }
            if entryModel.entry.imported == nil {
                return ["entry missing from import '\(entryLabel)'"]
            }

            return entryModel.properties.compactMap { property in
                guard entryModel.isChanged(prop: property) else { return nil }
                return "entry '\(entryLabel)' property '\(property.displayName)': existing='\((entryModel.existingValue(for: property) ?? "nil").importLogPreview)' imported='\((entryModel.importedValue(for: property) ?? "nil").importLogPreview)' merged='\((entryModel.mergedValue(for: property) ?? "nil").importLogPreview)'"
            }
        }
    }

    @MainActor
    func commonItemDifferences(existing: any ItemDataAccessible, imported: any ItemDataAccessible) -> [String] {
        var differences: [String] = []

        appendImportDifference("id", existing.id.uuidString, imported.id.uuidString, to: &differences)
        appendImportDifference("name", existing.name, imported.name, to: &differences)
        appendImportDifference("description", existing.description, imported.description, to: &differences)
        appendImportDifference("tags", existing.tags.joined(separator: ","), imported.tags.joined(separator: ","), to: &differences)
        appendImportDifference("category", "\(existing.category.rawValue)", "\(imported.category.rawValue)", to: &differences)
        appendImportDifference("displayState", "\(existing.displayState)", "\(imported.displayState)", to: &differences)
        appendImportDifference("isGroupHiddenToggle", "\(existing.isGroupHiddenToggle)", "\(imported.isGroupHiddenToggle)", to: &differences)
        appendImportDifference("parentId", existing.parentId?.uuidString ?? "nil", imported.parentId?.uuidString ?? "nil", to: &differences)
        differences += fileDifferences(existing: existing.fileUrl, imported: imported.fileUrl)
        differences += entryDifferences(existing: existing.entries, imported: imported.entries)

        return differences
    }

    func fileDifferences(existing: FileUrl?, imported: FileUrl?) -> [String] {
        var differences: [String] = []
        appendImportDifference("file.id", existing?.fileId.uuidString ?? "nil", imported?.fileId.uuidString ?? "nil", to: &differences)
        appendImportDifference("file.url", existing?.rawUrl.absoluteString ?? "nil", imported?.rawUrl.absoluteString ?? "nil", to: &differences)
        appendImportDifference("file.location", existing.map { "\($0.location)" } ?? "nil", imported.map { "\($0.location)" } ?? "nil", to: &differences)
        appendImportDifference("file.module", existing?.module ?? "nil", imported?.module ?? "nil", to: &differences)
        appendImportDifference("file.contentHash", existing?.contentHash ?? "nil", imported?.contentHash ?? "nil", to: &differences)
        return differences
    }

    func entryDifferences(existing: [any EntryDataAccessible], imported: [any EntryDataAccessible]) -> [String] {
        var differences: [String] = []
        let existingIds = existing.map(\.id)
        let importedIds = imported.map(\.id)
        appendImportDifference("entry.ids", existingIds.map(\.uuidString).joined(separator: ","), importedIds.map(\.uuidString).joined(separator: ","), to: &differences)

        // Indexed by id, see `SingleItemImportModel.from(item:)`. See CODE_AUDIT_21 §7.2.
        var seenIds: Set<UUID> = []
        let allIds = (existingIds + importedIds).filter { seenIds.insert($0).inserted }
        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let importedById = Dictionary(imported.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for id in allIds {
            let existingEntry = existingById[id]
            let importedEntry = importedById[id]
            let entryPrefix = "entry \(id.uuidString)"

            guard let existingEntry, let importedEntry else {
                appendImportDifference("\(entryPrefix).presence", existingEntry == nil ? "missing" : "present", importedEntry == nil ? "missing" : "present", to: &differences)
                continue
            }

            appendImportDifference("\(entryPrefix).childId", existingEntry.childId.uuidString, importedEntry.childId.uuidString, to: &differences)
            appendImportDifference("\(entryPrefix).name", existingEntry.name, importedEntry.name, to: &differences)
            appendImportDifference("\(entryPrefix).content", existingEntry.content, importedEntry.content, to: &differences)
            appendImportDifference("\(entryPrefix).displayState", "\(existingEntry.displayState)", "\(importedEntry.displayState)", to: &differences)
        }

        return differences
    }

    func appendImportDifference(_ label: String, _ existing: String, _ imported: String, to differences: inout [String]) {
        guard existing != imported else { return }
        differences.append("\(label): existing='\(existing.importLogPreview)' imported='\(imported.importLogPreview)'")
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
            await itemControllable.reset(fileUrl: stored, item: &item)
            return (false, ImportedFileWrite(written: stored, previous: localFileUrl))
        } catch {
            guard !requiresDurableFile else { throw error }
            Logger.importController.error("Cannot store the delivered file \(module, privacy: .public), keeping it in memory for the game")
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
    @MainActor
    func shouldDeferGameModeFolderImport(_ item: ModelType, writesGameMemory: Bool) -> Bool {
        guard writesGameMemory, let imported = item as? Model else { return false }
        return imported.category == .folder
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
        imported.entries.removeAll { locallyReusedFileIds.contains($0.childId) }
        return imported.entries.isEmpty ? nil : imported
    }

    @MainActor
    func normalizeImportedItemForMerge(in item: inout Model) {
        ImportItemRepair.normalizeLegacyCategory(in: &item)

        if config.module == .photo && item.category == .entry {
            item.entries = []
        }
    }
}

private extension Array where Element == String {
    var importLogSummary: String {
        guard !isEmpty else { return "none" }
        let maxItems = 16
        let visibleItems = prefix(maxItems)
        let summary = visibleItems.joined(separator: " | ")
        let remainingCount = count - visibleItems.count
        guard remainingCount > 0 else { return summary }
        return "\(summary) | +\(remainingCount) more"
    }
}

private extension String {
    var importLogPreview: String {
        let maxLength = 240
        let flattened = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("\n", with: "\\n")
            .replacing("\r", with: "\\r")
        guard flattened.count > maxLength else { return flattened }
        return "\(String(flattened.prefix(maxLength)))..."
    }
}

// MARK: - Binary Stream Reading

extension InputStream {
    func readHeader() throws -> GmzFileHeader {
        GmzFileHeader(counter: try readCounter(), token: try readCounter(), version: try readCounter())
    }

    /// Reads the next module header while treating a clean stream boundary as normal EOF.
    /// File-backed input streams can report `hasBytesAvailable == true` until one final read,
    /// so scanning optional trailing modules cannot use that property alone.
    func readOptionalHeader() throws -> GmzFileHeader? {
        var readBuffer = [UInt8](repeating: 0, count: 4)
        let readCount = read(&readBuffer, maxLength: readBuffer.count)
        guard readCount != 0 else { return nil }
        guard readCount == readBuffer.count else {
            throw ItemDataImportableError.notEnoughData
        }

        let counter = readBuffer.reversed().reduce(UInt32(0)) { result, byte in
            result << 8 | UInt32(byte)
        }
        return GmzFileHeader(
            counter: Int(counter),
            token: try readCounter(),
            version: try readCounter()
        )
    }

    func readItemHeader() throws -> (Int, Int) {
        (try readCounter(), try readCounter())
    }

    func readCounter() throws -> Int {
        var readBuffer = [UInt8](repeating: 0, count: 4)
        let readCount = read(&readBuffer, maxLength: readBuffer.count)
        guard readCount == readBuffer.count else {
            throw ItemDataImportableError.notEnoughData
        }

        let u32 = readBuffer.reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        return Int(u32)
    }

    /// Upper bound on a single item/file block's declared size. `size` below comes
    /// straight off the wire (a 4-byte counter, up to ~4.29 billion) with nothing else
    /// validating it first — without this cap a single corrupted or malicious header
    /// (from a bad import file, or a peer's SharePlay/Bonjour network payload) would
    /// make `readData(size:)` attempt a multi-gigabyte allocation before the
    /// subsequent `read` call ever gets a chance to fail with `.notEnoughData`. See
    /// CODE_AUDIT_Import §6.1. 512 MB comfortably covers the largest legitimate single
    /// blob this format carries (an embedded PDF or 3D object file) with headroom.
    static let maxSingleBlockSize = 512 * ByteUnit.mebibyte

    func readData(size: Int) throws -> Data {
        guard size >= 0, size <= Self.maxSingleBlockSize else {
            throw ItemDataImportableError.notEnoughData
        }
        // Read in bounded chunks instead of allocating `size` bytes up front: a truncated
        // file with a large declared size used to allocate (and zero) up to 512 MB before
        // the first read could fail, and a partial read was treated as a failure.
        // See CODE_AUDIT_15 §5.7.
        var data = Data()
        data.reserveCapacity(min(size, Self.readChunkSize))
        var chunk = [UInt8](repeating: 0, count: min(size, Self.readChunkSize))
        while data.count < size {
            let wanted = min(chunk.count, size - data.count)
            let readCount = read(&chunk, maxLength: wanted)
            guard readCount > 0 else {
                throw ItemDataImportableError.notEnoughData
            }
            data.append(chunk, count: readCount)
        }
        return data
    }

    private static let readChunkSize = ByteUnit.mebibyte
}
