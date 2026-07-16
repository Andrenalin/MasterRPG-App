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
    @MainActor func updatePin(itemId: UUID, data: Data?, playerId: UUID) -> Bool
    func hasBackgroundImage(itemId: UUID) async -> Bool
    func missingMapImages(itemId: UUID) async -> [NetworkCodableDataType]
    @MainActor func movePin(itemId: UUID, pinId: UUID, location: CGPoint) -> Bool
    @MainActor func togglePin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func zoomPin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func toggleDeadPin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func resizePin(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func toggleHighlightPin(itemId: UUID, pinId: UUID) -> Bool
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
    func updatePin(itemId: UUID, data: Data?, playerId: UUID) -> Bool {
        guard let data, let incomingPin = MapPinModel.decodeData(of: data) else { return false }
        let now = Date.now.timeIntervalSince1970
        guard incomingPin.timeInterval.isFinite,
              incomingPin.timeInterval <= now + Self.maximumFuturePinTimestampSkew else {
            return false
        }

        // Player-origin updates are valid only for maps registered in the
        // active game. Falling back to the persistent editor item here would
        // let a forged map id mutate content that was never shared.
        guard let item = gameModel.itemData[itemId] as? MapModel else { return false }
        if item.pointer.id == incomingPin.id {
            guard item.pointer.isShown,
                  incomingPin.timeInterval > item.pointer.timeInterval,
                  incomingPin.location != item.pointer.location else {
                return false
            }
            // The pointer is never a regular pin: players may move it while it
            // is visible, but none of its other fields are accepted.
            item.pointer.location = incomingPin.location
            item.pointer.timeInterval = incomingPin.timeInterval
            return true
        }

        guard let pinIndex = item.mapPins.firstIndex(where: { $0.id == incomingPin.id }) else {
            // Player updates may never create map pins or session-player pins.
            return false
        }
        let currentPin = item.mapPins[pinIndex]
        guard incomingPin.timeInterval > currentPin.timeInterval else { return false }

        let isOwnedPlayerPin = currentPin.isPlayer && currentPin.id == playerId
        guard isOwnedPlayerPin || currentPin.isShown else { return false }

        var authorizedPin = currentPin
        if isOwnedPlayerPin {
            authorizedPin.location = incomingPin.location
        }
        // Zoom and highlight are the only shared interactions permitted on a
        // visible foreign pin. All metadata and game-master state stay intact.
        authorizedPin.isZoom = incomingPin.isZoom
        authorizedPin.isHighlighted = incomingPin.isHighlighted

        guard authorizedPin.location != currentPin.location
                || authorizedPin.isZoom != currentPin.isZoom
                || authorizedPin.isHighlighted != currentPin.isHighlighted else {
            return false
        }

        authorizedPin.timeInterval = incomingPin.timeInterval
        item[MapPinId.id, authorizedPin.id] = authorizedPin
        if authorizedPin.isPlayer,
           let playerPinIndex = mapGameModel.playerPins.firstIndex(where: { $0.id == authorizedPin.id }) {
            mapGameModel.playerPins[playerPinIndex] = authorizedPin
        }
        return true
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
        updatePinState(itemId: itemId, pinId: pinId) { pin in
            pin.location = location
        }
    }

    /// Toggles a pin's visibility as the game master — the 3D-table
    /// equivalent of the 2D game-master double tap.
    @MainActor
    func togglePin(itemId: UUID, pinId: UUID) -> Bool {
        updatePinState(itemId: itemId, pinId: pinId) { pin in
            pin.isShown.toggle()
        }
    }

    /// Toggles a pin's zoom state — visible to all participants via mapState.
    @MainActor
    func zoomPin(itemId: UUID, pinId: UUID) -> Bool {
        updatePinState(itemId: itemId, pinId: pinId) { pin in
            pin.isZoom.toggle()
        }
    }

    /// Toggles the persistent death marker as an authoritative game-master action.
    @MainActor
    func toggleDeadPin(itemId: UUID, pinId: UUID) -> Bool {
        updatePinState(itemId: itemId, pinId: pinId) { pin in
            pin.isDead.toggle()
        }
    }

    /// Cycles through the same pin sizes offered by the full map editor.
    @MainActor
    func resizePin(itemId: UUID, pinId: UUID) -> Bool {
        updatePinState(itemId: itemId, pinId: pinId) { pin in
            pin.size = pin.size.nextSize()
        }
    }

    /// Optimistically toggles a shared player highlight before `.mapPin` is sent.
    @MainActor
    func toggleHighlightPin(itemId: UUID, pinId: UUID) -> Bool {
        updatePinState(itemId: itemId, pinId: pinId) { pin in
            pin.isHighlighted.toggle()
        }
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
    static let maximumFuturePinTimestampSkew: TimeInterval = 5 * 60

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
                // Preserve only fields a player may optimistically change while
                // awaiting the authoritative round trip. Visibility, size, death,
                // and metadata always come from the game-master mapState.
                model.mapPins = incoming.map { incomingPin in
                    guard let local = model.mapPins.first(where: { $0.id == incomingPin.id }),
                          local.timeInterval > incomingPin.timeInterval else {
                        return incomingPin
                    }
                    var mergedPin = incomingPin
                    if incomingPin.isPlayer {
                        mergedPin.location = local.location
                    }
                    mergedPin.isZoom = local.isZoom
                    mergedPin.isHighlighted = local.isHighlighted
                    mergedPin.timeInterval = local.timeInterval
                    return mergedPin
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

    /// Applies a local pin mutation and gives it a monotonic timestamp. This is
    /// used by both authoritative master actions and optimistic player actions.
    @MainActor
    private func updatePinState(
        itemId: UUID,
        pinId: UUID,
        mutation: (inout MapPinModel) -> Void
    ) -> Bool {
        let item = gameItem(for: itemId)
        guard var pin = item.mapPins.first(where: { $0.id == pinId }) else { return false }
        mutation(&pin)
        pin.timeInterval = max(Date.now.timeIntervalSince1970, pin.timeInterval.nextUp)
        item[MapPinId.id, pinId] = pin
        if pin.isPlayer,
           let index = mapGameModel.playerPins.firstIndex(where: { $0.id == pinId }) {
            mapGameModel.playerPins[index] = pin
        }
        return true
    }
}
