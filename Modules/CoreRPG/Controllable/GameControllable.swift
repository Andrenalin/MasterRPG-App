// @copyright André Trettin

import Foundation
import Observation
import os.log

public protocol GameControllable: Sendable {
    // other controllers
    var itemControllable: any ItemControllable { get }
    var exportControllable: any ExportControllable { get }
    
    // model data
    var gameModel: ItemGameModel { get }

    // overwrite methods
    @MainActor func allPlayersReported(for id: UUID) -> Bool
    @MainActor func report(itemId: UUID, for player: UUID)

    // item manipluator
    var currentId: UUID { get async }

    @MainActor func resetGameState()
    
    // focus
    func focus(on id: UUID?) async
    func focus(on focusIds: [UUID]) async

    // network game data
    func networkVersion(for itemId: UUID) async -> Int
    /// `@concurrent`: the export streams multi-MB file bytes; as a plain nonisolated async
    /// requirement it ran on the (main-actor) caller's executor at ~15 call sites. It hops to
    /// the main actor itself where it has to. See CODE_AUDIT_18 §7.1.
    @concurrent func createGameData(for itemId: UUID) async throws -> NetworkCodableDataType
    func share(id: UUID) async -> NetworkCodableDataType
    func reveal(itemId: UUID, data: NetworkCodableDataType, save: Bool) async throws -> Bool
    func updateGame(data: NetworkCodableDataType, hide: Bool, deep: Bool) async throws
}

public enum ItemGameStorableError: Error {
    case memoryStreamError
    case networkDecoding
    case wrongData
    case itemMissing
}

public extension GameControllable {
    var currentId: UUID {
        get async {
            // `currentItemId` is itself `@MainActor` (inherited from `ItemGameModel`'s class
            // annotation) — `await` alone hops there, no `MainActor.run` wrapper needed.
            await gameModel.currentItemId ?? UUID()
        }
    }

    /// A pure availability/version check — used for reference lookups such as
    /// a map's pin photos (`GameController+Pins.missingMapImages`) or a
    /// proxy repair check (`MasterController.canServeProxyRequest`), not
    /// just direct reveals. Caches the item's data via `append` (not
    /// `insert`) when it isn't tracked yet, so a not-yet-cached *reference*
    /// (e.g. a monster pin's photo, checked while sending its map) is never
    /// promoted to `currentItemId` — `ItemGameModel.currentItemId` is
    /// literally `items.first`, and `insert(itemId:item:)` always places the
    /// new item at index 0. Before this fix, checking a pin photo's
    /// availability made it "current" the same way an actual reveal does,
    /// which `GameRootViewer`'s `onChange(of: ...currentItemId)` can't tell
    /// apart from a real reveal — silently popping the spatial photo window
    /// open for a pin's photo the GM never explicitly revealed. Only an
    /// explicit reveal path (`reveal(itemId:data:save:)`,
    /// `setCurrent(itemId:)`) should ever call `insert` and change what's
    /// current.
    @MainActor func hasItem(id: UUID, version: Int) async -> Bool {
        guard gameModel.itemData[id] != nil, let localItem = await itemControllable.item(for: id) else {
            guard let item = await itemControllable.item(for: id, version: version) else { return false }
            let gameItem = item.copy()
            gameModel.append(itemId: item.id, item: gameItem)
            return true
        }
        return version == 0 || version == localItem.version

    }

    func setCurrent(itemId: UUID) async -> Bool {
        if await gameModel.moveToFront(itemId: itemId) {
            return true
        }

        guard let item = await itemControllable.item(for: itemId),
              // A caller that was superseded while the item loaded must not change the game.
              !Task.isCancelled
        else { return false }
        await gameModel.insert(itemId: item.id, item: item)
        return true
    }

    func reset() async {
        await itemControllable.itemDataModel.resetGame()
        await gameModel.reset()
        await resetGameState()
        await removeGameMemoryFiles()
    }

    /// Removes the files imports wrote for items that only lived in this game's memory (game
    /// deliveries, a loaded saved game), unless a library item references them by now.
    /// See CODE_AUDIT_Folder §5.26.
    @MainActor
    private func removeGameMemoryFiles() async {
        guard let controller = itemControllable.fileUrlDataController else { return }
        let files = controller.model.gameMemoryFiles
        controller.model.gameMemoryFiles = []
        await itemControllable.removeUnreferencedGameFiles(files)
    }
    
    @MainActor func resetGameState() {}

    @MainActor
    func report(itemId: UUID, for player: UUID) {
        gameModel.setPlayerReport(playerId: player, for: itemId)
    }
    
    func focus(on id: UUID?) async {
        await performFocus(on: id)
    }

    @MainActor
    private func performFocus(on id: UUID?) {
        let newFocusId = id ?? gameModel.currentItemId
        if let newFocusId {
            gameModel.focus(on: [newFocusId])
        }
    }

    func focus(on focusIds: [UUID]) async {
        await gameModel.focus(on:focusIds)
    }

    @concurrent func createGameData(for itemId: UUID) async throws -> NetworkCodableDataType {
        // `exporting(ids:)` silently drops an id it cannot find instead of
        // failing, so an absent item would otherwise export as an empty-but-
        // valid payload. Callers such as MasterController's reveal handlers
        // depend on `try?` turning "master does not own this item" into a
        // clean `nil` rather than a corrupt canonical broadcast.
        guard await itemControllable.item(for: itemId) != nil else {
            throw ItemGameStorableError.itemMissing
        }
        // Persist a deterministic content hash before exporting so the sender's
        // version and the metadata imported by the receiver describe the same
        // bytes.
        await backfillContentHashIfNeeded(itemId: itemId)

        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }

        // A package for players: the module exporters leave out what only the game master may
        // see. See CODE_AUDIT_22 §6.2.
        try await ExportAudience.$current.withValue(.players) {
            let itemIds = await exportControllable.exporting(ids: Set([itemId]))
            _ = try await exportControllable.rootExportController.export(itemIds: itemIds, into: stream)
        }

        guard let data = stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data else {
            throw ItemGameStorableError.memoryStreamError
        }
        let version = await networkVersion(for: itemId)
        let module = itemControllable.config.module
        return NetworkCodableDataType(id: itemId, type: module, version: version, data: data)
    }

    /// Returns the deterministic version used on the wire, lazily backfilling
    /// legacy file metadata first. Map networking uses this for its referenced
    /// background photo without exporting that photo merely to learn its
    /// version.
    func networkVersion(for itemId: UUID) async -> Int {
        await backfillContentHashIfNeeded(itemId: itemId)
        return await itemControllable.item(for: itemId)?.version ?? -1
    }

    /// A file attached through the picker (`EditControllable.resetFile`) never gets a
    /// content hash — only network imports compute one (see the "Nil for legacy items
    /// whose data was never seen on this device" note on `FileUrl.contentHash`). Left
    /// alone, this item's `version` falls back to the update-UUID, which shares no
    /// relationship with the content hash a receiver computes for the same bytes on
    /// import — so `hasItem`'s version comparison would never agree. Backfill it once,
    /// lazily, right before this item's version is sent over the network.
    @MainActor
    private func backfillContentHashIfNeeded(itemId: UUID) async {
        guard let fileUrlDataController = itemControllable.fileUrlDataController else { return }
        guard let fileUrl = itemControllable.itemSync(for: itemId)?.fileUrl, fileUrl.contentHash == nil else { return }
        // Streamed from disk off the main actor, not loaded whole. See CODE_AUDIT_Folder §7.1.
        guard let contentHash = try? await fileUrlDataController.contentHash(for: fileUrl) else { return }
        // The file may have been replaced while it loaded: only stamp the hash onto the file
        // that was read. The hash is written as a field update on a copy — setting it on the
        // stored instance and calling `replace` compared the instance with itself and never
        // persisted. See CODE_AUDIT_Folder §3.11.
        guard itemControllable.itemSync(for: itemId)?.fileUrl == fileUrl else { return }
        let hashedFileUrl = FileUrl(
            fileId: fileUrl.fileId,
            url: fileUrl.rawUrl,
            location: fileUrl.location,
            module: fileUrl.module,
            relativeUrl: nil,
            contentHash: contentHash
        )
        itemControllable.persistFileUrl(hashedFileUrl, itemId: itemId)
    }

    func share(id: UUID) async -> NetworkCodableDataType {
        let version = await networkVersion(for: id)
        return NetworkCodableDataType(id: id, type: itemControllable.config.module, version: version)
    }
    
    /// Whether the item's backing file (if any) can be read on this device now. An iCloud Drive
    /// file that has not downloaded does not count (see `hasDownloadedData(for:)`), so the game
    /// gets the bytes from the peer instead of waiting on iCloud.
    /// Items without a file trivially return true.
    func hasLocalFileData(for itemId: UUID) async -> Bool {
        guard let fileUrlDataController = itemControllable.fileUrlDataController else { return true }
        guard let fileUrl = await itemControllable.item(for: itemId)?.fileUrl else { return true }
        return await fileUrlDataController.hasDownloadedData(for: fileUrl)
    }

    /// Like `hasLocalFileData(for:)`, but an iCloud file that has not downloaded is waited for
    /// instead of reported missing. Every game send (a show, a player's request, a pin photo)
    /// uses this: the file is downloaded first, even if that takes a while. Returns `false`
    /// only when the file never arrives or the caller is cancelled.
    func awaitLocalFileData(for itemId: UUID) async -> Bool {
        guard let fileUrlDataController = itemControllable.fileUrlDataController else { return true }
        guard let fileUrl = await itemControllable.item(for: itemId)?.fileUrl else { return true }
        if await fileUrlDataController.hasDownloadedData(for: fileUrl) { return true }
        Logger.fileStore.info("Waiting for the iCloud download of \(itemId, privacy: .public) before it is sent")
        return await fileUrlDataController.waitUntilDownloaded(fileUrl)
    }

    /// The size in bytes of the item's backing file on this device, `nil` for an item without a
    /// file or one that is not here. The game master shows it next to the share button.
    func fileByteCount(for itemId: UUID) async -> Int? {
        guard let fileUrlDataController = itemControllable.fileUrlDataController,
              let fileUrl = await itemControllable.item(for: itemId)?.fileUrl else { return nil }
        return await fileUrlDataController.byteCount(of: fileUrl)
    }

    func reveal(itemId: UUID, data: NetworkCodableDataType, save: Bool) async throws -> Bool {
        let generation = await gameModel.resetGeneration
        // Version 0 means the model has no version of its own (Dice, Adventure, Generator, …),
        // not "any version": a delivered package is imported instead of being dropped because a
        // copy exists. See CODE_AUDIT_Folder §5.24.
        let isAlreadyPresent: Bool
        if data.version == 0, data.data != nil {
            isAlreadyPresent = false
        } else {
            isAlreadyPresent = await hasItem(id: itemId, version: data.version)
        }
        guard !isAlreadyPresent else {
            if await !hasLocalFileData(for: itemId) {
                guard data.data != nil else { return false }
                try await updateGame(data: data, hide: !save, deep: false)
                return await hasLocalFileData(for: itemId)
            }
            return await completeReveal(itemId: itemId, save: save, generation: generation)
        }
        guard data.data != nil else { return false }
        try await updateGame(data: data, hide: !save, deep: false)
        return await hasLocalFileData(for: itemId)
    }

    /// Makes an already-available item current (and persists it for `save`) in one main-actor
    /// step, after checking the game was not reset while `reveal` awaited the file checks.
    /// See CODE_AUDIT_Folder §3.11.
    @MainActor
    private func completeReveal(itemId: UUID, save: Bool, generation: Int) -> Bool {
        guard gameModel.resetGeneration == generation else { return false }
        if !gameModel.moveToFront(itemId: itemId), let item = itemControllable.itemSync(for: itemId) {
            gameModel.insert(itemId: item.id, item: item)
        }
        if save, let model = gameModel.itemData[itemId] {
            itemControllable.persistFromGame(model: model, authoritative: false)
        }
        return true
    }

    /// Imports a delivered package without a `PeerImportPolicy`. The master also calls this for
    /// a player's asset package when it has no copy of the revealed item, so a connected player
    /// could in principle replace items of any module in the master's game.
    ///
    /// Accepted by design, never to be fixed (CODE_AUDIT_Folder §6.1): only players the game
    /// master knows can connect. SharePlay runs among FaceTime friends, a local-network game is
    /// played by people at the same table, and a public local-network game needs its join code.
    func updateGame(data: NetworkCodableDataType, hide: Bool, deep: Bool) async throws {
        try await updateGame(data: data, hide: hide, deep: deep, policy: hide ? .memoryOnly : .persist, importMode: .merge)
    }

    /// Overload of the protocol-required `updateGame(data:hide:deep:)` that
    /// lets a caller opt into `.overwrite` (see the `importMode` doc below).
    /// `importMode` has no default here deliberately — a default would make
    /// this ambiguous with the exact-match, protocol-required overload above
    /// for a bare `updateGame(data:hide:deep:)` call site.
    func updateGame(data: NetworkCodableDataType, hide: Bool, deep: Bool, importMode: ImportMode) async throws {
        try await updateGame(data: data, hide: hide, deep: deep, policy: hide ? .memoryOnly : .persist, importMode: importMode)
    }

    /// `importMode` defaults to `.merge` (the historical CRDT last-writer-wins
    /// behavior, keyed on each device's own local wall clock) for every
    /// existing caller. Pass `.overwrite` when the sender is unconditionally
    /// authoritative for this data — e.g. the master's own map broadcasts —
    /// so a player's stale local copy (from before this session, or a first
    /// reveal/repair resend) can never silently win the merge and discard
    /// what the master just sent. See CODE_AUDIT / player-character-sync-gaps.
    func updateGame(data: NetworkCodableDataType, hide: Bool, deep: Bool, policy: GameMutationPolicy, importMode: ImportMode = .merge) async throws {
        let generation = await gameModel.resetGeneration
        var appliedIds: Set<UUID> = []
        if let encodedData = data.data {
            do {
                // A delivery that is stored in the library needs its file on disk: the in-memory
                // fallback of a failed write was persisted as a reference to a file that does
                // not exist after relaunch. See CODE_AUDIT_21 §5.14.
                appliedIds = try await importNetwork(
                    from: encodedData,
                    importMode: importMode,
                    requiresDurableFiles: policy == .persist
                )[itemControllable.config.module] ?? []
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ItemGameStorableError.networkDecoding
            }
        } else {
            let module = itemControllable.config.module
            guard data.type == module else { throw ItemGameStorableError.wrongData }
        }
        try await applyGameUpdate(
            itemId: data.id,
            hide: hide,
            policy: policy,
            dependentIds: appliedIds.subtracting([data.id]),
            authoritative: importMode == .overwrite,
            generation: generation
        )
    }

    /// Shows (and for `.persist` stores) the delivered item in one main-actor step. A game reset
    /// during the import above must not re-populate the cleared game model or persist the
    /// delivery, so the reset generation is re-checked here. See CODE_AUDIT_Folder §3.11.
    ///
    /// `.persist` also stores the other items of this module the package wrote (a playlist's
    /// tracks, a character's grouped values); the old dependent list was always empty, so they
    /// stayed in game memory and vanished at game end. Each is merged with the library copy and
    /// keeps its local folder and visibility. See CODE_AUDIT_Folder §5.22, §5.23.
    @MainActor
    private func applyGameUpdate(itemId: UUID, hide: Bool, policy: GameMutationPolicy, dependentIds: Set<UUID>, authoritative: Bool, generation: Int) throws {
        guard gameModel.resetGeneration == generation else { throw CancellationError() }
        let gameItem: ModelType? = gameModel.item(for: itemId)
        guard let item = gameItem ?? itemControllable.itemSync(for: itemId) else { throw ItemGameStorableError.itemMissing }
        gameModel.apply(itemId: itemId, item: item, hide: hide)
        guard policy == .persist else { return }
        itemControllable.persistFromGame(model: item, authoritative: authoritative)
        for dependent in members(of: itemId, within: dependentIds) {
            itemControllable.persistFromGame(model: dependent, authoritative: authoritative)
        }
    }

    /// The items of `candidateIds` reachable from `itemId` through `entries` (a playlist's
    /// tracks, a collection's members, recursively). Other items of the package — the sender's
    /// ancestor folders or collections that contain the delivered item — describe the sender's
    /// library and are not persisted with it. See CODE_AUDIT_Folder §5.22.
    @MainActor
    private func members(of itemId: UUID, within candidateIds: Set<UUID>) -> [ModelType] {
        func gameOrLibraryItem(_ id: UUID) -> ModelType? {
            let gameItem: ModelType? = gameModel.item(for: id)
            return gameItem ?? itemControllable.itemSync(for: id)
        }
        var found: [ModelType] = []
        var visited: Set<UUID> = [itemId]
        var stack = [itemId]
        while let current = stack.popLast(), visited.count <= candidateIds.count + 1 {
            guard let item = gameOrLibraryItem(current) as? any ItemDataAccessible else { continue }
            for childId in item.entries.map(\.childId) where candidateIds.contains(childId) && visited.insert(childId).inserted {
                if let child = gameOrLibraryItem(childId) {
                    found.append(child)
                    stack.append(childId)
                }
            }
        }
        return found
    }
    
    @MainActor
    func allPlayersReported(for id: UUID) -> Bool {
        let players = gameModel.playerReport(for: id)
        return gameModel.currentPlayers.filter { !players.contains($0) }.isEmpty
    }
}

public extension GameControllable {
    /// Whether everyone of the running game has `itemId`, as far as this device knows. A
    /// player device counts the game master as well. Without players nothing is shared.
    @MainActor
    func isSharedWithEveryone(_ itemId: UUID) -> Bool {
        !gameModel.currentPlayers.isEmpty && allPlayersReported(for: itemId)
    }

    /// Runs off the caller's (usually main) actor: parsing the byte stream reads blocks of up to
    /// 512 MB. Model creation and storage still hop to the main actor per item.
    /// See CODE_AUDIT_15 §3.3.
    /// Returns the ids each module's import wrote (see `ItemDataImportModel.appliedItemIds`).
    @concurrent @discardableResult
    func importNetwork(from data: Data, forceSave: Bool = false, importMode: ImportMode = .merge, peerPolicy: PeerImportPolicy? = nil, requiresDurableFiles: Bool = false) async throws -> [NetworkModules: Set<UUID>] {
        // A bulk import or repair holds the data-mutation lock: apply this package after it
        // instead of interleaving with its writes. See CODE_AUDIT_Folder §3.5.
        await DataMutationCoordinator.shared.waitUntilIdle()
        try Task.checkCancellation()
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        let importController = await exportControllable.rootImportController
        let importModel = await ItemDataImportModel(importMode: importMode, peerPolicy: peerPolicy, requiresDurableFiles: requiresDurableFiles)
        try await importController.importStream(from: stream, forceSave: forceSave, importModel: importModel)
        return await importModel.appliedItemIds
    }
}
