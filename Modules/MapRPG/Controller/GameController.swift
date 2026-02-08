// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

@MainActor @Observable
final class MapGameModel: Sendable {
    init() {}

    var playerPins: [MapPinModel] = []
    
    func reset() {
        playerPins = []
    }
}

public protocol MapGameStorable {
    @MainActor func setPlayerPin(for playerId: UUID, name: String, characterId: UUID)
    @MainActor func resetPlayerPins(for players: [PlayerGameModel])
    @MainActor func updatePin(itemId: UUID, data: Data?, playerId: UUID)
    func missingPlayerImages(itemId: UUID) async -> [NetworkCodableDataType]
    @MainActor func updateMap(for itemId: UUID, with data: NetworkCodableDataType)
    @MainActor func mapUpdateResult(for itemId: UUID) -> String
    @MainActor func networkMapUpdate(for itemId: UUID) -> NetworkCodableDataType
    @MainActor func saveAll() -> ItemModuleIds
    
    @MainActor func demoNextMap(itemId: UUID, restart: Bool) -> NetworkCodableDataType?
    
    @MainActor func startGameAsMaster()
}

struct GameController: Sendable {
    @MainActor
    init(rootManager: RootManager, root: MapRootModel, itemController: ItemController, linkRegisterController: LinkRegisterController, rootExportControllable: any ExportControllable, rootImportControllable: any ImportControllable) {
        self.rootManager = rootManager
        self.root = root
        self.itemController = itemController
        self.exportController = ExportController(rootManager: rootManager, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(config: root.config, photoRoot: root.photoRoot, dataController: nil, linkRegisterController: linkRegisterController)
        self.importController = ImportController(itemController: internItemController, gameImporter: true)
        self.rootExportControllable = rootExportControllable
        self.rootImportControllable = rootImportControllable
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
        self.mapGameModel = MapGameModel()
    }

    let rootManager: RootManager
    let root: MapRootModel
    let itemController: ItemController
    let exportController: ExportController
    let importController: ImportController
    let rootExportControllable: any ExportControllable
    let rootImportControllable: any ImportControllable

    let gameModel: ItemGameModel
    let mapGameModel: MapGameModel

    @MainActor
    func gameItem(for itemId: UUID) -> MapModel {
        (gameModel.itemData[itemId] as? MapModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor
    func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor
    func currentItem() -> MapModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    
    func resetGameState() {
        mapGameModel.reset()
    }
}

extension GameController: MapGameStorable {
    @MainActor func startGameAsMaster() {
        root.rootModel.toolBarModel.displayMode = .master
    }
    
    @MainActor
    func setPlayerPin(for playerId: UUID, name: String, characterId: UUID) {
        let photoId = root.characterRoot.valueGameControllable.playerPinPhoto(for: characterId)

        if let index = mapGameModel.playerPins.firstIndex(where: { $0.id == playerId }) {
            mapGameModel.playerPins[index].photoId = photoId
        } else {
            let pin = MapPinModel(id: playerId, name: name, color: Color.random, photoId: photoId, size: .normal, isPlayer: true, players: [playerId])
            mapGameModel.playerPins.append(pin)
        }
    }

    @MainActor
    func resetPlayerPins(for players: [PlayerGameModel]) {
        let playerIds = players.map { $0.id }
        let removedIds = Set(mapGameModel.playerPins.map { $0.id }).subtracting(playerIds)
        removedIds.forEach { playerId in
            if let index = mapGameModel.playerPins.firstIndex(where: { $0.id == playerId }) {
                let pin = mapGameModel.playerPins.remove(at: index)
                for itemId in gameModel.items {
                    gameItem(for: itemId).mapPins.removeAll(where: { $0.id == pin.id })
                }
            }
        }
        for player in players {
            guard let characterId = player.characterId else { continue }
            setPlayerPin(for: player.id, name: player.name, characterId: characterId)

            guard let pin = mapGameModel.playerPins.first(where: { $0.id == player.id }) else { continue }
            for itemId in gameModel.items {
                if gameItem(for: itemId).mapPins.contains(where: { $0.id == pin.id }) == false {
                    gameItem(for: itemId).mapPins.append(pin)
                }
            }
        }
    }

    @MainActor
    func updatePin(itemId: UUID, data: Data?, playerId: UUID) {
        guard let data, let pin = MapPinModel.decodeData(of: data) else {
            fatalError("MapPinModel expected")
        }
        if gameItem(for: itemId).pointer.id == pin.id {
            if gameItem(for: itemId).pointer.isShown {
                gameItem(for: itemId).pointer.location = pin.location
            }
            return
        }
        if let index = mapGameModel.playerPins.firstIndex(where: { $0.id == pin.id }) {
            if pin.timeInterval > mapGameModel.playerPins[index].timeInterval {
                mapGameModel.playerPins[index] = pin
            }
        } else {
            mapGameModel.playerPins.append(pin)
        }

        if let pinIndex = gameItem(for: itemId).mapPins.firstIndex(where: { $0.id == pin.id }) {
            if pin.timeInterval > gameItem(for: itemId).mapPins[pinIndex].timeInterval {
                gameItem(for: itemId)[MapPinId.id, pin.id] = pin
            }
        } else {
            gameItem(for: itemId).mapPins.append(pin)
        }
    }

    func missingPlayerImages(itemId: UUID) async -> [NetworkCodableDataType] {
        let model = await gameItem(for: itemId)
        var result: [NetworkCodableDataType] = []
        for pin in model.mapPins.filter({ $0.isPlayer }) {
            if let photoId = pin.photoId, await !root.photoRoot.gameControllable.hasItem(id: photoId, version: 0) {
                await result.append(root.photoRoot.gameControllable.share(id: photoId))
            }
        }
        return result
    }

    @MainActor
    func updateMap(for itemId: UUID, with data: NetworkCodableDataType) {
        guard let mapData = data.data, let text = String(data: mapData, encoding: .utf8) else { return }
        updateMap(for: itemId, with: text)
    }

    @MainActor
    func mapUpdateResult(for itemId: UUID) -> String {
        let model = gameItem(for: itemId)
        let first = model.entries.reduce("") { $0 + "\($1.id):\($1.isShown):\($1.focused)|" }
        return first + (JSONString.encode(value: [model.pointer] + model.mapPins) ?? "")
    }

    @MainActor
    func networkMapUpdate(for itemId: UUID) -> NetworkCodableDataType {
        NetworkCodableDataType(id: itemId, type: .map, version: 0, data: mapUpdateResult(for: itemId).data(using: .utf8))
    }

    func networkPin(itemId: UUID, position: MapPinModel) -> NetworkCodableDataType {
        NetworkCodableDataType(id: itemId, type: .map, version: 0, data: position.encodeData())
    }
    
    @MainActor
    func saveAll() -> ItemModuleIds {
        let gameExportController = ExportController(rootManager: rootManager, itemController: importController.itemController, gameExporter: true)
        for itemId in gameModel.items {
            gameItem(for: itemId).mapPins = gameItem(for: itemId).mapPins.filter { !$0.isPlayer }
        }
        return gameExportController.exportingAll()
    }
    
    @MainActor
    func demoNextMap(itemId: UUID, restart: Bool) -> NetworkCodableDataType? {
        let item = gameItem(for: itemId)
        if restart {
            item.entries.forEach {
                item.toggle($0.id)
            }
            return networkMapUpdate(for: itemId)
        }
        guard let firstEntry = item.entries.first(where: { !$0.isShown }) else { return nil }
        item.toggle(firstEntry.id)
        return networkMapUpdate(for: itemId)
    }
}

private extension GameController {
    @MainActor
    private func updateMap(for itemId: UUID, with result: String) {
        let model = gameItem(for: itemId)

        var entries = model.entries

        let subData = result.split(separator: "|")
        if let positionText = subData.last {
            if let mapPins: [MapPinModel] = JSONString.decode(text: positionText) {
                if let pointer = mapPins.first {
                    model.pointer = pointer
                }
                model.mapPins = Array(mapPins.dropFirst())
            }
        }

        subData.dropLast().forEach {
            let entryState = $0.split(separator: ":")
            guard let uuidString = entryState.first, let entryId = UUID(uuidString: String(uuidString)) else { return }

            let shown = entryState[1] == "true"
            let focused = entryState.last ?? "false" == "true"
            guard let entryIndex = entries.firstIndex(where: { $0.id == entryId }) else { return }
            entries[entryIndex].isShown = shown
            entries[entryIndex].focused = focused
        }
        model.entries = entries
    }
}
