// @copyright André Trettin

import Foundation
import Observation

@MainActor
public protocol ItemGameReportable {
    var players: [UUID] { get set }
}

@MainActor @Observable
public final class ItemGameModel {
    public typealias ModelType = Observable & Sendable
    
    public init(itemDataModel: ItemDataModel) {
        self.itemDataModel = itemDataModel
    }

    public let itemDataModel: ItemDataModel
    public var items: [UUID] {
        get { itemDataModel.gameItems }
        set { itemDataModel.gameItems = newValue }
    }
    public var itemData: [UUID: ModelType] {
        get { itemDataModel.gameItemData }
        set { itemDataModel.gameItemData = newValue }
    }
    public var focusItemIds: [UUID] = []

    public var currentItemId: UUID? {
        itemDataModel.gameItems.first
    }

    public var currentPlayers: [UUID] = []

    // Per-item player-reporting state for the current game session.
    // Stored here (not on domain models) to avoid shared state across game sessions
    // and to prevent cross-test contamination when tests run in parallel.
    public var playerReports: [UUID: [UUID]] = [:]

    public func setCurrent(players: [UUID]) {
        currentPlayers = players
    }

    public func playerReport(for itemId: UUID) -> [UUID] {
        playerReports[itemId] ?? []
    }

    public func setPlayerReport(playerId: UUID, for itemId: UUID) {
        if playerReports[itemId] == nil {
            playerReports[itemId] = [playerId]
        } else if !playerReports[itemId]!.contains(playerId) {
            playerReports[itemId]!.append(playerId)
        }
    }

    public func removePlayerReport(for playerId: UUID) {
        playerReports = playerReports.mapValues { players in
            players.filter { $0 != playerId }
        }
    }
    
    func append(itemId: UUID, item: ModelType, onlyItem: Bool = false) {
        if !onlyItem {
            items.append(itemId)
        }
        itemData[itemId] = item
    }

    func append(itemId: UUID) {
        items.append(itemId)
    }

    func insert(itemId: UUID, item: ModelType) {
        items.insert(itemId, at: 0)
        itemData[itemId] = item
    }
    
    /// Finds `itemId` and moves it to the front in one synchronous step, so no `await` gap can
    /// shrink `items` between the lookup and the removal. Returns whether it was present.
    /// See CODE_AUDIT_16 §3.10.
    func moveToFront(itemId: UUID) -> Bool {
        guard let index = items.firstIndex(of: itemId) else { return false }
        if index != 0 {
            items.remove(at: index)
            items.insert(itemId, at: 0)
        }
        return true
    }

    func insert(itemId: UUID, at index: Int?, removeIndex: Int?) {
        if let removeIndex {
            items.remove(at: removeIndex)
        }
        if let index {
            items.insert(itemId, at: index)
        } else {
            items.append(itemId)
        }
    }

    /// Reads `items` itself, synchronously, as the "previously visible" baseline —
    /// rather than taking it as a parameter read by the caller before an `await` gap —
    /// so a concurrent call can't mutate `items` in between the read and this mutation.
    /// See CODE_AUDIT_EditItem §3.3.
    func apply(itemId: UUID, item: ModelType, hide: Bool) -> [ModelType] {
        let previousIds = items
        if hide {
            if !items.contains(itemId) {
                items.append(itemId)
            }
        } else if let index = items.firstIndex(of: itemId) {
            if index != 0 {
                items.remove(at: index)
                items.insert(itemId, at: 0)
            }
        } else {
            items.insert(itemId, at: 0)
        }

        itemData[itemId] = item
        guard !hide else { return [] }
        return Set(items)
            .subtracting(previousIds)
            .subtracting([itemId])
            .compactMap { itemData[$0] }
    }

    func item(for itemId: UUID) -> ModelType? {
        itemData[itemId]
    }
    
    func reset() {
        items = []
        itemData.removeAll()
        playerReports.removeAll()
    }

    func focus(on focusIds: [UUID]) {
        focusItemIds = focusIds
    }
}

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

        guard let item = await itemControllable.item(for: itemId) else { return false }
        await gameModel.insert(itemId: item.id, item: item)
        return true
    }

    func reset() async {
        await itemControllable.itemDataModel.resetGame()
        await gameModel.reset()
        await resetGameState()
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
        let itemIds = await exportControllable.exporting(ids: Set([itemId]))

        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }

        _ = try await exportControllable.rootExportController.export(itemIds: itemIds, into: stream)

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
        guard var item = await itemControllable.item(for: itemId), let fileUrl = item.fileUrl, fileUrl.contentHash == nil else { return }
        guard let data = try? await fileUrlDataController.loadData(for: fileUrl) else { return }
        item.fileUrl = FileUrl(
            fileId: fileUrl.fileId,
            url: fileUrl.rawUrl,
            location: fileUrl.location,
            module: fileUrl.module,
            relativeUrl: nil,
            contentHash: FileUrl.contentHash(of: data)
        )
        itemControllable.replaceForGame(model: item, isInsert: true, policy: .persist)
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

    func reveal(itemId: UUID, data: NetworkCodableDataType, save: Bool) async throws -> Bool {
        guard await hasItem(id: itemId, version: data.version) == false else {
            if await !hasLocalFileData(for: itemId) {
                guard data.data != nil else { return false }
                try await updateGame(data: data, hide: !save, deep: false)
                return await hasLocalFileData(for: itemId)
            }
            _ = await setCurrent(itemId: itemId)
            if save, let model = await gameModel.itemData[itemId] {
                await itemControllable.replaceForGame(model: model, isInsert: true, policy: .persist)
            }
            return true
        }
        guard data.data != nil else { return false }
        try await updateGame(data: data, hide: !save, deep: false)
        return await hasLocalFileData(for: itemId)
    }

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
        if let encodedData = data.data {
            do {
                try await importNetwork(from: encodedData, importMode: importMode)
            } catch {
                throw ItemGameStorableError.networkDecoding
            }
        } else {
            let module = itemControllable.config.module
            guard data.type == module else { throw ItemGameStorableError.wrongData }
        }

        var item = await gameModel.item(for: data.id)
        if item == nil {
            item = await itemControllable.item(for: data.id)
        }
        guard let item else { throw ItemGameStorableError.itemMissing }
        let otherItems = await gameModel.apply(itemId: data.id, item: item, hide: hide)
        if policy == .persist {
            await itemControllable.replaceForGame(model: item, isInsert: true, policy: .persist)
            for otherItem in otherItems {
                await itemControllable.replaceForGame(model: otherItem, isInsert: true, policy: .persist)
            }
        }
    }
    
    @MainActor
    func allPlayersReported(for id: UUID) -> Bool {
        let players = gameModel.playerReport(for: id)
        return gameModel.currentPlayers.filter { !players.contains($0) }.isEmpty
    }
}

public extension GameControllable {
    /// Runs off the caller's (usually main) actor: parsing the byte stream reads blocks of up to
    /// 512 MB. Model creation and storage still hop to the main actor per item.
    /// See CODE_AUDIT_15 §3.3.
    @concurrent
    func importNetwork(from data: Data, forceSave: Bool = false, importMode: ImportMode = .merge, peerPolicy: PeerImportPolicy? = nil) async throws {
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        let importController = await exportControllable.rootImportController
        let importModel = await ItemDataImportModel(importMode: importMode, peerPolicy: peerPolicy)
        try await importController.importStream(from: stream, forceSave: forceSave, importModel: importModel)
    }
}
