// @copyright André Trettin

import Foundation
import Observation

public protocol ItemGameReportable {
    var players: [UUID] { get set }
}

@MainActor @Observable
public final class ItemGameModel: Sendable {
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
    
    public func setCurrent(players: [UUID]) {
        currentPlayers = players
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

    func item(for itemId: UUID) -> ModelType? {
        itemData[itemId]
    }
    
    func reset() {
        items = []
        itemData.removeAll()
    }

    func focus(on focusIds: [UUID]) {
        focusItemIds = focusIds
    }
}

public protocol GameControllable: Sendable {
    // other controllers
    var itemControllable: any ItemControllable { get }
    var exportControllable: any ExportControllable { get }
    var importControllable: any ImportControllable { get }
    
    // model data
    var gameModel: ItemGameModel { get }

    // overwrite methods
    func updateGame(data: NetworkCodableDataType, subtype: RPGMessageActionType) async throws
    @MainActor func allPlayersReported(for id: UUID) -> Bool
    @MainActor func report(itemId: UUID, for player: UUID)

    // item manipluator
    var currentId: UUID { get async }

    @MainActor
    func resetGameState()
    
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
            await gameModel.currentItemId ?? UUID()
        }
    }

    func hasItem(id: UUID, version: Int) async -> Bool {
        guard await gameModel.itemData[id] == nil else {
            if version == 0 {
                return true
            }
            // the item should be imported
            if await importControllable.itemControllable.itemDataModel.items.contains(id) {
                return await importControllable.itemControllable.item(for: id, version: version) != nil
            }
            return await itemControllable.item(for: id, version: version) != nil
        }
        
        guard let item = await itemControllable.item(for: id, version: version) else { return false }
        await gameModel.insert(itemId: item.id, item: item)
        return true
    }

    func setCurrent(itemId: UUID) async -> Bool {
        if let index = await gameModel.items.firstIndex(where: { $0 == itemId }) {
            if index != 0 {
                let id = await gameModel.items[index]
                await gameModel.insert(itemId: id, at: 0, removeIndex: index)
            }
            return true
        }

        guard let item = await itemControllable.item(for: itemId) else { return false }
        await gameModel.insert(itemId: item.id, item: item)
        return true
    }

    func reset() async {
        await gameModel.reset()
        await resetGameState()
    }
    
    func resetGameState() {}

    @MainActor
    func report(itemId: UUID, for player: UUID) {
        var item = gameModel.itemData[itemId] as? ItemGameReportable
        if item == nil {
            item = itemControllable.itemSync(for: itemId) as? ItemGameReportable
        }
        guard var item else { return }
        if !item.players.contains(player) {
            item.players.append(player)
        }
    }
    
    func focus(on id: UUID?) async {
        let currentId = await gameModel.currentItemId
        let newFocusId = id ?? currentId
        if let newFocusId {
            await gameModel.focus(on: [newFocusId])
        }
    }

    func focus(on focusIds: [UUID]) async {
        await gameModel.focus(on:focusIds)
    }

    func createGameData(for itemId: UUID) async throws -> NetworkCodableDataType {
        let itemIds = await exportControllable.exporting(ids: Set([itemId]))

        let stream = OutputStream.toMemory()
        stream.open()

        do {
            let _ = try await exportControllable.rootExportController.export(itemIds: itemIds, into: stream) { _, _ in }
        } catch {
            print(error.localizedDescription)
        }

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
                await itemControllable.replace(model: model, isInsert: true)
            }
            return true
        }
        guard data.data != nil else { return false }
        try await updateGame(data: data, hide: !save, deep: false)
        return true
    }

    func updateGame(data: NetworkCodableDataType, hide: Bool, deep: Bool) async throws {
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
        if hide {
            await gameModel.append(itemId: data.id)
        } else {
            let index = await gameModel.items.firstIndex(where: { $0 == data.id })
            await gameModel.insert(itemId: data.id, at: 0, removeIndex: (index ?? 0 > 0 ? index : nil))
        }
        await gameModel.append(itemId: data.id, item: item, onlyItem: true)
        if !hide {
            await itemControllable.replace(model: item, isInsert: true)
            var otherIds = await Set(gameModel.items).subtracting(beforeIds)
            otherIds = otherIds.subtracting([data.id])
            for otherId in otherIds {
                let otherItem = await gameModel.itemData[otherId]
                await itemControllable.replace(model: otherItem, isInsert: true)
            }
        }
    }
    
    @MainActor
    func allPlayersReported(for id: UUID) -> Bool {
        var item = gameModel.itemData[id]
        if item == nil {
            item = itemControllable.itemSync(for: id)
        }
        guard let players = (item as? ItemGameReportable)?.players else { return false }
        return gameModel.currentPlayers.filter { !players.contains($0) }.isEmpty
    }
}

public extension GameControllable {
    func importNetwork(from data: Data) async throws {
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        try await exportControllable.rootManager.adventureRoot.importControllable.importStream(from: stream, counterUpdater: {})
    }
}
