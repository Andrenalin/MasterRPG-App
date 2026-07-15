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
    func mapAssetVersion(for itemId: UUID) async -> Int
    @MainActor func mapContentVersion(for itemId: UUID) -> Int
    func shareMap(id: UUID) async -> NetworkCodableDataType
    func createMapGameData(for itemId: UUID) async throws -> NetworkCodableDataType
    func networkMapContentUpdate(for itemId: UUID) async -> NetworkCodableDataType
    @MainActor func applyMapContentUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool

    @MainActor func setPlayerPin(for playerId: UUID, name: String, characterId: UUID)
    @MainActor func resetPlayerPins(for players: [PlayerGameModel])
    @MainActor func updatePin(itemId: UUID, data: Data?, playerId: UUID)
    func hasBackgroundImage(itemId: UUID) async -> Bool
    func missingMapImages(itemId: UUID) async -> [NetworkCodableDataType]
    @MainActor func movePin(itemId: UUID, pinId: UUID, location: CGPoint) -> Bool
    @MainActor func togglePin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func networkPin(itemId: UUID, pinId: UUID) -> NetworkCodableDataType?
    @MainActor func updateMap(for itemId: UUID, with data: NetworkCodableDataType)
    @MainActor func mapUpdateResult(for itemId: UUID) -> String
    @MainActor func networkMapUpdate(for itemId: UUID) -> NetworkCodableDataType
    @MainActor func saveAll() -> ItemModuleIds
    
    @MainActor func demoNextMap(itemId: UUID, restart: Bool) -> NetworkCodableDataType?
    
    @MainActor func startGameAsMaster()
}

struct GameController: Sendable {
    @MainActor init(root: MapRootModel, itemController: ItemController, exportController: ExportController) {
        self.root = root
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.mapGameModel = MapGameModel()
    }

    let root: MapRootModel
    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let mapGameModel: MapGameModel

    @MainActor func gameItem(for itemId: UUID) -> MapModel {
        (gameModel.itemData[itemId] as? MapModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> MapModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        mapGameModel.reset()
    }
}

extension GameController: MapGameStorable {
    func mapAssetVersion(for itemId: UUID) async -> Int {
        let backgroundPhotoId = await MainActor.run {
            gameItem(for: itemId).photoId
        }
        let backgroundPhotoVersion: Int?
        if let backgroundPhotoId {
            backgroundPhotoVersion = await root.photoRoot.gameControllable.networkVersion(for: backgroundPhotoId)
        } else {
            backgroundPhotoVersion = nil
        }
        return MapAssetFingerprint(
            mapId: itemId,
            backgroundPhotoId: backgroundPhotoId,
            backgroundPhotoVersion: backgroundPhotoVersion
        ).version
    }

    @MainActor
    func mapContentVersion(for itemId: UUID) -> Int {
        MapUpdatePayload(model: gameItem(for: itemId)).contentVersion
    }

    func shareMap(id: UUID) async -> NetworkCodableDataType {
        let metadata = await MainActor.run {
            let item = gameItem(for: id)
            return (version: item.version, contentVersion: MapUpdatePayload(model: item).contentVersion)
        }
        let assetVersion = await mapAssetVersion(for: id)
        return NetworkCodableDataType(
            id: id,
            type: .map,
            version: metadata.version,
            assetVersion: assetVersion,
            contentVersion: metadata.contentVersion
        )
    }

    func createMapGameData(for itemId: UUID) async throws -> NetworkCodableDataType {
        // Compute the referenced photo version first. The generic photo
        // controller lazily backfills its content hash, and the following full
        // export then carries that same stable metadata to the receiver.
        let assetVersion = await mapAssetVersion(for: itemId)
        let base = try await createGameData(for: itemId)
        let contentVersion = await mapContentVersion(for: itemId)
        return NetworkCodableDataType(
            id: base.id,
            type: base.type,
            version: base.version,
            data: base.data,
            assetVersion: assetVersion,
            contentVersion: contentVersion
        )
    }

    func networkMapContentUpdate(for itemId: UUID) async -> NetworkCodableDataType {
        let metadata = await MainActor.run {
            let item = gameItem(for: itemId)
            let payload = MapUpdatePayload(model: item)
            return (
                version: item.version,
                contentVersion: payload.contentVersion,
                data: payload.encodedData()
            )
        }
        let assetVersion = await mapAssetVersion(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: metadata.version,
            data: metadata.data,
            assetVersion: assetVersion,
            contentVersion: metadata.contentVersion
        )
    }

    @MainActor
    func applyMapContentUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        guard data.id == itemId,
              data.type == .map,
              let payload = MapUpdatePayload.decodeData(data.data),
              payload.isSupported,
              payload.snapshot.id == itemId,
              data.contentVersion == nil || data.contentVersion == payload.contentVersion,
              let model = gameModel.itemData[itemId] as? MapModel else {
            return false
        }
        payload.snapshot.apply(to: model)
        return true
    }

    /// Commits an editor working copy into the already-observed game map before
    /// the toolbar creates a structural update. Maps that are not in the active
    /// game are deliberately left alone.
    @MainActor
    func refreshSharedMap(from editedMap: MapModel) -> Bool {
        guard let gameMap = gameModel.itemData[editedMap.id] as? MapModel else { return false }
        MapSnapshot(editedMap).apply(to: gameMap)
        return true
    }

    @MainActor func startGameAsMaster() {
        root.rootModel.gameEditorModel?.displayMode = .master
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

    /// Whether the map's background photo is usable on this device. A map
    /// without one is trivially complete.
    @MainActor func hasBackgroundImage(itemId: UUID) async -> Bool {
        guard let backgroundPhotoId = gameItem(for: itemId).photoId else { return true }
        return await hasPhotoImage(for: backgroundPhotoId)
    }

    @MainActor func missingMapImages(itemId: UUID) async -> [NetworkCodableDataType] {
        let model = gameItem(for: itemId)
        // A live map-state snapshot can introduce ordinary monster/character
        // pins as well as player-owned pins after the full map was imported.
        // Only their photos participate in this repair scan. The background is
        // part of the full map package and must stay on that transfer path.
        let photoIds = model.mapPins.compactMap { $0.photoId }
        var result: [NetworkCodableDataType] = []
        var uniquePhotoIds: Set<UUID> = []
        for photoId in photoIds where uniquePhotoIds.insert(photoId).inserted {
            // SharePlay repairs model ownership, not the independent iCloud
            // download state. `hasItem` checks the photo game controller first,
            // then the persistent item controller.
            guard await !root.photoRoot.gameControllable.hasItem(id: photoId, version: 0) else { continue }
            await result.append(root.photoRoot.gameControllable.share(id: photoId))
        }
        return result
    }

    @MainActor private func hasPhotoImage(for photoId: UUID) async -> Bool {
        // hasItem alone is true for a metadata-only photo whose binary never
        // arrived — the file check sends recovery back through the full map.
        let hasItem = await root.photoRoot.gameControllable.hasItem(id: photoId, version: 0)
        let hasFile = await root.photoRoot.gameControllable.hasLocalFileData(for: photoId)
        return hasItem && hasFile
    }

    /// Moves a pin as the game master: updates the game item and the shared
    /// player-pin state by id, stamping `timeInterval` so receivers can resolve
    /// conflicts — the 3D-table equivalent of the 2D game-master drag.
    @MainActor
    func movePin(itemId: UUID, pinId: UUID, location: CGPoint) -> Bool {
        let item = gameItem(for: itemId)
        guard var pin = item.mapPins.first(where: { $0.id == pinId }) else { return false }
        pin.location = location
        pin.timeInterval = Date.now.timeIntervalSince1970
        item[MapPinId.id, pinId] = pin
        if let index = mapGameModel.playerPins.firstIndex(where: { $0.id == pinId }) {
            mapGameModel.playerPins[index] = pin
        }
        return true
    }

    /// Toggles a pin's visibility as the game master — the 3D-table
    /// equivalent of the 2D game-master double tap.
    @MainActor
    func togglePin(itemId: UUID, pinId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        guard var pin = item.mapPins.first(where: { $0.id == pinId }) else { return false }
        pin.isShown.toggle()
        pin.timeInterval = Date.now.timeIntervalSince1970
        item[MapPinId.id, pinId] = pin
        if let index = mapGameModel.playerPins.firstIndex(where: { $0.id == pinId }) {
            mapGameModel.playerPins[index] = pin
        }
        return true
    }

    /// Encodes the current state of a single pin for a `.mapPin` message —
    /// the player-origin route to the master.
    @MainActor
    func networkPin(itemId: UUID, pinId: UUID) -> NetworkCodableDataType? {
        guard let pin = gameItem(for: itemId).mapPins.first(where: { $0.id == pinId }) else { return nil }
        return networkPin(itemId: itemId, position: pin)
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
        let item = gameItem(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: item.version,
            data: mapUpdateResult(for: itemId).data(using: .utf8),
            contentVersion: mapContentVersion(for: itemId)
        )
    }

    func networkPin(itemId: UUID, position: MapPinModel) -> NetworkCodableDataType {
        NetworkCodableDataType(id: itemId, type: .map, version: 0, data: position.encodeData())
    }
    
    @MainActor
    func saveAll() -> ItemModuleIds {
        for itemId in gameModel.items {
            gameItem(for: itemId).mapPins = gameItem(for: itemId).mapPins.filter { !$0.isPlayer }
        }
        return exportController.exportingAll()
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
                let incoming = Array(mapPins.dropFirst())
                // For player pins, keep the local version when it is newer than the
                // received snapshot — prevents a stale master broadcast from overwriting
                // a pin that the player has already moved.
                model.mapPins = incoming.map { incomingPin in
                    if incomingPin.isPlayer,
                       let local = model.mapPins.first(where: { $0.id == incomingPin.id }),
                       local.timeInterval > incomingPin.timeInterval {
                        return local
                    }
                    return incomingPin
                }
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
