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

    func apply(itemId: UUID, item: ModelType, hide: Bool, previousIds: [UUID]) -> [ModelType] {
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
    func updateGame(data: NetworkCodableDataType, subtype: RPGMessageActionType) async throws
    @MainActor func allPlayersReported(for id: UUID) -> Bool
    @MainActor func report(itemId: UUID, for player: UUID)

    // item manipluator
    var currentId: UUID { get async }

    @MainActor func resetGameState()
    
    // focus
    func focus(on id: UUID?) async
    func focus(on focusIds: [UUID]) async

    // network game data
    func createGameData(for itemId: UUID) async throws -> NetworkCodableDataType
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
    func updateGame(data: NetworkCodableDataType, subtype: RPGMessageActionType) async throws {}

    var currentId: UUID {
        get async {
            await MainActor.run {
                gameModel.currentItemId ?? UUID()
            }
        }
    }

    @MainActor func hasItem(id: UUID, version: Int) async -> Bool {
        guard gameModel.itemData[id] != nil, let localItem = await itemControllable.item(for: id) else {
            guard let item = await itemControllable.item(for: id, version: version) else { return false }
            let gameItem = item.copy()
            gameModel.insert(itemId: item.id, item: gameItem)
            return true
        }
        return version == 0 || version == localItem.version

    }

    func setCurrent(itemId: UUID) async -> Bool {
        let existing = await MainActor.run { () -> (id: UUID, index: Int)? in
            guard let index = gameModel.items.firstIndex(where: { $0 == itemId }) else { return nil }
            return (id: gameModel.items[index], index: index)
        }
        if let existing {
            if existing.index != 0 {
                await gameModel.insert(itemId: existing.id, at: 0, removeIndex: existing.index)
            }
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
        await MainActor.run {
            let newFocusId = id ?? gameModel.currentItemId
            if let newFocusId {
                gameModel.focus(on: [newFocusId])
            }
        }
    }

    func focus(on focusIds: [UUID]) async {
        await gameModel.focus(on:focusIds)
    }

    func createGameData(for itemId: UUID) async throws -> NetworkCodableDataType {
        let itemIds = await exportControllable.exporting(ids: Set([itemId]))

        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }

        _ = try await exportControllable.rootExportController.export(itemIds: itemIds, into: stream)

        guard let data = stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data else {
            throw ItemGameStorableError.memoryStreamError
        }
        let version = await itemControllable.item(for: itemId)?.version ?? -1
        let module = itemControllable.config.module
        return NetworkCodableDataType(id: itemId, type: module, version: version, data: data)
    }

    func share(id: UUID) async -> NetworkCodableDataType {
        await NetworkCodableDataType(id: id, type: itemControllable.config.module, version: itemControllable.item(for: id)?.version ?? -1)
    }
    
    func reveal(itemId: UUID, data: NetworkCodableDataType, save: Bool) async throws -> Bool {
        guard await hasItem(id: itemId, version: data.version) == false else {
            _ = await setCurrent(itemId: itemId)
            if save, let model = await gameModel.itemData[itemId] {
                await itemControllable.replaceForGame(model: model, isInsert: true, policy: .persist)
            }
            return true
        }
        guard data.data != nil else { return false }
        try await updateGame(data: data, hide: !save, deep: false)
        return true
    }

    func updateGame(data: NetworkCodableDataType, hide: Bool, deep: Bool) async throws {
        try await updateGame(data: data, hide: hide, deep: deep, policy: hide ? .memoryOnly : .persist)
    }

    func updateGame(data: NetworkCodableDataType, hide: Bool, deep: Bool, policy: GameMutationPolicy) async throws {
        let beforeIds = await gameModel.items
        if let encodedData = data.data {
            do {
                try await importNetwork(from: encodedData)
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
        let otherItems = await gameModel.apply(itemId: data.id, item: item, hide: hide, previousIds: beforeIds)
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
    func importNetwork(from data: Data, forceSave: Bool = false) async throws {
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        let importController = await exportControllable.rootImportController
        try await importController.importStream(from: stream, forceSave: forceSave)
    }
}
