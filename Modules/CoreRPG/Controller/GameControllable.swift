// @copyright André Trettin

import Foundation
import Observation

public protocol ItemGameReportable {
    var players: [UUID] { get set }
}

@MainActor @Observable
public final class ItemGameModel: Sendable {
    public init(items: [UUID] = [], itemData: [UUID : ItemDataCodableModel] = [:], focusItemIds: [UUID] = [], currentItemId: UUID? = nil, currentPlayers: [UUID] = []) {
        self.items = items
        self.itemData = itemData
        self.focusItemIds = focusItemIds
        self.currentItemId = currentItemId
        self.currentPlayers = currentPlayers
    }
    
    public var items: [UUID]
    public var itemData: [UUID: ItemDataCodableModel]
    public var focusItemIds: [UUID]

    public var reports: [UUID: [UUID]] = [:]
    
    public var currentItemId: UUID?
    public var currentPlayers: [UUID]
    
    public func setCurrent(players: [UUID]) {
        currentPlayers = players.sorted()
    }
    
    func append(itemId: UUID, item: ItemDataCodableModel, onlyItem: Bool = false) {
        if !onlyItem {
            items.append(itemId)
        }
        itemData[itemId] = item
    }

    func append(itemId: UUID) {
        items.append(itemId)
    }

    func insert(itemId: UUID, item: ItemDataCodableModel) {
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

    func item(for itemId: UUID) -> ItemDataCodableModel? {
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
//    var rootExportControllable: any ExportControllable { get }
//    var rootImportControllable: any ImportControllable { get }
    
    // model data
    var gameModel: ItemGameModel { get }

    // overwrite methods
    func updateGame(data: NetworkCodableDataType, subtype: RPGMessageActionType) async throws
    @MainActor func allPlayersReported(for id: UUID, deep: Int) -> Bool
    @MainActor func report(itemId: UUID, for player: UUID)

    // item manipluator
    var currentId: UUID { get async }

    @MainActor func startGame(with id: UUID)
    @MainActor func resetGameState()
    @MainActor func saveAll() -> ItemModuleIds?
        
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
    @MainActor
    func allPlayersReported(for id: UUID, deep: Int) -> Bool {
        guard deep < 10 else { return false }
        guard gameModel.reports[id] == gameModel.currentPlayers else { return false }
        return true
    }

    @MainActor
    func gameItem(for itemId: UUID) -> ItemDataCodableModel? {
        gameModel.itemData[itemId] ?? itemControllable.itemDataCodableModel(id: itemId)
    }
    
    @MainActor
    func setGame(item: ItemDataCodableModel, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor
    func currentItem() -> ItemDataCodableModel? {
        guard let currentId = gameModel.currentItemId else { return nil }
        return gameItem(for: currentId)
    }

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
            return await itemControllable.item(for: id, version: version) == false
        }
        
        guard await itemControllable.item(for: id, version: version) else { return false }
        guard let itemCodable = await importControllable.itemControllable.itemDataCodableModel(id: id) else { return false }
        await gameModel.insert(itemId: id, item: itemCodable)
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

        guard let item = await itemControllable.itemDataCodableModel(for: itemId) else { return false }
        await gameModel.insert(itemId: item.id, item: item)
        return true
    }

    func reset() async {
        await gameModel.reset()
        await resetGameState()
    }
    
    @MainActor func startGame(with id: UUID) {}
    @MainActor func resetGameState() {}
    @MainActor func saveAll() -> ItemModuleIds? { nil }

    @MainActor
    func report(itemId: UUID, for player: UUID) {
        var players = gameModel.reports[itemId, default: []]
        if !players.contains(player) {
            players.append(player)
            players = players.sorted()
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
            //let _ = try await rootExportControllable.export(itemIds: itemIds, into: stream) { _, _ in }
            let _ = try await exportControllable.export(itemIds: itemIds, into: stream) { _, _ in }
        } catch {
            print(error.localizedDescription)
        }

        guard let data = stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data else {
            throw ItemGameStorableError.memoryStreamError
        }
        let version = await itemControllable.itemVersion(for: itemId) ?? -1
        return NetworkCodableDataType(id: itemId, type: itemControllable.module, version: version, data: data)
    }

    func share(id: UUID) async -> NetworkCodableDataType {
        let version = await itemControllable.itemVersion(for: id) ?? -1
        return NetworkCodableDataType(id: id, type: itemControllable.module, version: version)
    }
    
    func reveal(itemId: UUID, data: NetworkCodableDataType, save: Bool) async throws -> Bool {
        guard await hasItem(id: itemId, version: data.version) == false else {
            _ = await setCurrent(itemId: itemId)
            if save, let model = await gameModel.itemData[itemId] {
                await itemControllable.replace(model: model, isInsert: true, shouldRepairLinks: true)
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
            guard data.type == itemControllable.module else { throw ItemGameStorableError.wrongData }
        }

        var item = await gameModel.item(for: data.id)
        if item == nil {
            item = await itemControllable.itemDataCodableModel(id: data.id)
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
            await itemControllable.replace(model: item, isInsert: true, shouldRepairLinks: true)
            var otherIds = await Set(gameModel.items).subtracting(beforeIds)
            otherIds = otherIds.subtracting([data.id])
            for otherId in otherIds {
                let otherItem = await gameModel.itemData[otherId]
                await itemControllable.replace(model: otherItem, isInsert: true, shouldRepairLinks: true)
            }
        }
    }
}

private extension GameControllable {
    func importNetwork(from data: Data) async throws {
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        //try await rootImportControllable.importStream(from: stream, counterUpdater: {})
        try await importControllable.importStream(from: stream, counterUpdater: {})
    }
}
