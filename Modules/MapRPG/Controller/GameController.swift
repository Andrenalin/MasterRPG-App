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
    @MainActor func toggleRoom(itemId: UUID, roomId: UUID) -> Bool
    @MainActor func setRoomsShown(itemId: UUID, roomIds: [UUID], isShown: Bool) -> Bool
    @MainActor func movePointer(itemId: UUID, location: CGPoint) -> Bool
    @MainActor func togglePointer(itemId: UUID) -> Bool
    @MainActor func networkPointer(itemId: UUID) -> NetworkCodableDataType?
    @MainActor func addMonstersAtMapCenter(itemId: UUID, monsters: [ItemRowModel]) -> Bool
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
        // Export suspends while dependent assets are collected. Validate the
        // generation on both sides of that suspension so the bytes and their
        // advertised fingerprints cannot describe two different map edits.
        for _ in 0..<Self.maximumPackageExportAttempts {
            guard let before = await stablePackageMetadata(for: itemId) else { continue }
            let base = try await createGameData(for: itemId)
            guard let after = await stablePackageMetadata(for: itemId),
                  before == after,
                  base.version == after.version else {
                continue
            }
            return NetworkCodableDataType(
                id: base.id,
                type: base.type,
                version: after.version,
                data: base.data,
                assetVersion: after.assetVersion,
                contentVersion: after.contentVersion
            )
        }
        throw MapGameStorableError.packageChangedDuringExport
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
            mapGameModel.playerPins[index].name = name
            mapGameModel.playerPins[index].photoId = photoId
            mapGameModel.playerPins[index].characterId = characterId
            mapGameModel.playerPins[index].isPlayer = true
            mapGameModel.playerPins[index].players = [playerId]
        } else {
            let pin = MapPinModel(id: playerId, name: name, color: Color.random, photoId: photoId, characterId: characterId, size: .normal, isPlayer: true, players: [playerId])
            mapGameModel.playerPins.append(pin)
        }

        // A Character package can arrive after the roster has already placed
        // this player on one or more live maps. Refresh only the associated
        // metadata so every map gains the Character link without resetting its
        // independent position or other runtime state.
        guard let playerPin = mapGameModel.playerPins.first(where: { $0.id == playerId }) else { return }
        for itemId in gameModel.items {
            let map = gameItem(for: itemId)
            guard let index = map.mapPins.firstIndex(where: { $0.id == playerId }) else { continue }
            Self.applyPlayerMetadata(from: playerPin, to: &map.mapPins[index])
        }
    }

    @MainActor
    func resetPlayerPins(for players: [PlayerGameModel]) {
        let playerIds = Set(players.map(\.id))
        mapGameModel.playerPins.removeAll { !playerIds.contains($0.id) }
        // The roster is authoritative. Scan every live map as well as the
        // central cache because an older snapshot may hold a player pin that
        // is no longer represented in `mapGameModel.playerPins`.
        for itemId in gameModel.items {
            gameItem(for: itemId).mapPins.removeAll { pin in
                pin.isPlayer && !playerIds.contains(pin.id)
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

    /// Toggles a room using `MapModel`'s domain behavior. In particular, this
    /// preserves the hex-grid rule that revealing a hex also reveals rooms it
    /// intersects instead of duplicating that rule in a tabletop view.
    @MainActor
    func toggleRoom(itemId: UUID, roomId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        guard item.entries.contains(where: { $0.id == roomId }) else { return false }
        item.toggle(roomId)
        return true
    }

    /// Applies one room-visibility command to a collection of entries. Each
    /// changed room still travels through `MapModel.toggle(_:)`, and callers
    /// can therefore send one authoritative map-state update for the batch.
    @MainActor
    func setRoomsShown(itemId: UUID, roomIds: [UUID], isShown: Bool) -> Bool {
        let item = gameItem(for: itemId)
        var didChange = false
        for roomId in roomIds {
            guard let room = item.entries.first(where: { $0.id == roomId }),
                  room.isShown != isShown else { continue }
            item.toggle(roomId)
            didChange = true
        }
        return didChange
    }

    /// Moves the shared pointer while keeping its timestamp monotonic for the
    /// same player-to-master conflict resolution used by regular map pins.
    @MainActor
    func movePointer(itemId: UUID, location: CGPoint) -> Bool {
        let item = gameItem(for: itemId)
        guard item.pointer.location != location else { return false }
        item.pointer.location = location
        item.pointer.timeInterval = max(Date.now.timeIntervalSince1970, item.pointer.timeInterval.nextUp)
        return true
    }

    /// Shows or hides the shared pointer as an authoritative game-master action.
    @MainActor
    func togglePointer(itemId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        item.pointer.isShown.toggle()
        item.pointer.timeInterval = max(Date.now.timeIntervalSince1970, item.pointer.timeInterval.nextUp)
        return true
    }

    /// Encodes the current pointer for the player-origin `.mapPin` route.
    @MainActor
    func networkPointer(itemId: UUID) -> NetworkCodableDataType? {
        let item = gameItem(for: itemId)
        return networkPin(itemId: itemId, position: item.pointer)
    }

    /// Adds the selected characters to the center of the live game map. This
    /// lets a standalone tabletop add pawns without depending on MapEditor UI.
    @MainActor
    func addMonstersAtMapCenter(itemId: UUID, monsters: [ItemRowModel]) -> Bool {
        guard !monsters.isEmpty,
              gameModel.itemData[itemId] is MapModel else { return false }
        let item = gameItem(for: itemId)
        let initialCount = item.mapPins.count
        let center = CGPoint(x: item.width / 2, y: item.height / 2)
        root.editController.addMonsters(
            map: item,
            entryId: nil,
            location: center,
            monsters: monsters,
            number: 1
        )
        return item.mapPins.count > initialCount
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
            assetVersion: currentMapAssetVersion(for: itemId),
            contentVersion: mapContentVersion(for: itemId)
        )
    }

    @MainActor
    func networkPin(itemId: UUID, position: MapPinModel) -> NetworkCodableDataType {
        let item = gameItem(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: item.version,
            data: position.encodeData(),
            contentVersion: mapContentVersion(for: itemId)
        )
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
    static let maximumPackageExportAttempts = 3

    struct PackageMetadata: Equatable, Sendable {
        let version: Int
        let assetVersion: Int
        let contentVersion: Int
    }

    struct PackageCoreMetadata: Equatable, Sendable {
        let version: Int
        let contentVersion: Int
        let backgroundPhotoId: UUID?
    }

    func stablePackageMetadata(for itemId: UUID) async -> PackageMetadata? {
        for _ in 0..<Self.maximumPackageExportAttempts {
            let before = await packageCoreMetadata(for: itemId)
            let backgroundPhotoVersion: Int?
            if let photoId = before.backgroundPhotoId {
                backgroundPhotoVersion = await root.photoRoot.gameControllable.networkVersion(for: photoId)
            } else {
                backgroundPhotoVersion = nil
            }
            let after = await packageCoreMetadata(for: itemId)
            guard before == after else { continue }
            return PackageMetadata(
                version: after.version,
                assetVersion: MapAssetFingerprint(
                    mapId: itemId,
                    backgroundPhotoId: after.backgroundPhotoId,
                    backgroundPhotoVersion: backgroundPhotoVersion
                ).version,
                contentVersion: after.contentVersion
            )
        }
        return nil
    }

    @MainActor
    func packageCoreMetadata(for itemId: UUID) -> PackageCoreMetadata {
        let item = gameItem(for: itemId)
        return PackageCoreMetadata(
            version: item.version,
            contentVersion: MapUpdatePayload(model: item).contentVersion,
            backgroundPhotoId: item.photoId
        )
    }

    @MainActor
    func currentMapAssetVersion(for itemId: UUID) -> Int {
        let backgroundPhotoId = gameItem(for: itemId).photoId
        let backgroundPhotoVersion = backgroundPhotoId.flatMap { photoId in
            let gamePhoto = root.photoRoot.gameControllable.gameModel.itemData[photoId] as? PhotoModel
            let persistentPhoto = root.photoRoot.itemControllable.itemSync(for: photoId) as? PhotoModel
            return (gamePhoto ?? persistentPhoto)?.version
        }
        return MapAssetFingerprint(
            mapId: itemId,
            backgroundPhotoId: backgroundPhotoId,
            backgroundPhotoVersion: backgroundPhotoVersion
        ).version
    }

    static func applyPlayerMetadata(from source: MapPinModel, to destination: inout MapPinModel) {
        destination.name = source.name
        destination.color = source.color
        destination.photoId = source.photoId
        destination.characterId = source.characterId
        destination.isPlayer = true
        destination.players = source.players
    }

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
            let entryState = $0.split(separator: ":", omittingEmptySubsequences: false)
            guard entryState.count == 3,
                  let entryId = UUID(uuidString: String(entryState[0])),
                  let shown = Bool(String(entryState[1])),
                  let focused = Bool(String(entryState[2])),
                  let entryIndex = entries.firstIndex(where: { $0.id == entryId }) else {
                return
            }
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

private enum MapGameStorableError: Error {
    case packageChangedDuringExport
}
