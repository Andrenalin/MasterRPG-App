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
    struct AuthoritativeGeneration: Equatable, Sendable {
        let version: Int
        let assetVersion: Int
        let contentVersion: Int
    }

    init() {
        let settings = BattleRoundSettingsModel()
        let battleRound = BattleRoundModel()
        battleRound.initiativeOrder = settings.initiativeOrder
        battleRoundSettings = settings
        battleRoundModel = battleRound
    }

    var playerPins: [MapPinModel] = []
    let battleRoundModel: BattleRoundModel
    let battleRoundSettings: BattleRoundSettingsModel
    private(set) var battleCharacterCopyIds: Set<UUID> = []
    private var authoritativeGenerations: [UUID: AuthoritativeGeneration] = [:]
    private var lastActivatedRoomIds: [UUID: UUID] = [:]

    func recordAuthoritativeGeneration(_ data: NetworkCodableDataType) {
        guard data.type == .map else { return }
        guard let assetVersion = data.assetVersion,
              let contentVersion = data.contentVersion else {
            authoritativeGenerations[data.id] = nil
            return
        }
        authoritativeGenerations[data.id] = AuthoritativeGeneration(
            version: data.version,
            assetVersion: assetVersion,
            contentVersion: contentVersion
        )
    }

    func authoritativeGeneration(for itemId: UUID) -> AuthoritativeGeneration? {
        authoritativeGenerations[itemId]
    }

    func recordActivatedRoom(_ roomId: UUID, for mapId: UUID) {
        lastActivatedRoomIds[mapId] = roomId
    }

    func lastActivatedRoomId(for mapId: UUID) -> UUID? {
        lastActivatedRoomIds[mapId]
    }

    func registerBattleCharacterCopy(_ id: UUID) {
        battleCharacterCopyIds.insert(id)
    }

    func clearBattleCharacterCopies() {
        battleCharacterCopyIds = []
    }
    
    func reset() {
        playerPins = []
        authoritativeGenerations = [:]
        lastActivatedRoomIds = [:]
        battleCharacterCopyIds = []
        battleRoundModel.reset()
    }
}

public protocol MapGameStorable {
    @MainActor var battleRoundModel: BattleRoundModel { get }
    @MainActor var battleRoundSettings: BattleRoundSettingsModel { get }
    func mapAssetVersion(for itemId: UUID) async -> Int
    @MainActor func mapContentVersion(for itemId: UUID) -> Int
    @MainActor func recordAuthoritativeMapGeneration(_ data: NetworkCodableDataType)
    func shareMap(id: UUID) async -> NetworkCodableDataType
    func createMapGameData(for itemId: UUID) async throws -> NetworkCodableDataType
    func networkMapContentUpdate(for itemId: UUID) async -> NetworkCodableDataType
    @MainActor func applyMapContentUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool

    @MainActor func setPlayerPin(for playerId: UUID, name: String, characterId: UUID)
    @MainActor func resetPlayerPins(for players: [PlayerGameModel])
    @MainActor @discardableResult func synchronizePlayerPins(for itemId: UUID) -> Bool
    @MainActor func updatePin(itemId: UUID, data: Data?, playerId: UUID) -> Bool
    @MainActor func updatePinIfCurrentGeneration(
        itemId: UUID,
        data: NetworkCodableDataType,
        playerId: UUID
    ) -> Bool
    func hasBackgroundImage(itemId: UUID) async -> Bool
    func missingMapImages(itemId: UUID) async -> [NetworkCodableDataType]
    @MainActor func movePin(itemId: UUID, pinId: UUID, location: CGPoint) -> Bool
    @MainActor func toggleRoom(itemId: UUID, roomId: UUID) -> Bool
    @MainActor func toggleRoomFocus(itemId: UUID, roomId: UUID) -> Bool
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
    /// The player/room pins eligible to start a battle on `itemId` — pure
    /// map lookup (current map, focused/last-activated room, pins within
    /// it) — or nil if `itemId` isn't the current map or no pins qualify.
    @MainActor func battleStartPins(itemId: UUID) -> (playerPins: [MapPinModel], roomPins: [MapPinModel])?
    /// Resolves (creating a battle-only runtime copy if needed) the
    /// Character behind `pinId` and packages it as a `BattleCombatant`.
    /// Shared by `startBattle`/`addBattleCombatant` (compound, still called
    /// directly by the map editor and tested in isolation) and by
    /// `synchronizeBattleDefenders`, so it stays a single MapRPG primitive.
    @MainActor func makeBattleCombatant(itemId: UUID, pinId: UUID) -> BattleCombatant?
    /// Clears any highlighted pins on the map — battle start/end always
    /// begins from a clean highlight state.
    @MainActor func clearBattleHighlights(itemId: UUID)
    /// The actual domain mutation (`BattleRoundModel.begin`, settings,
    /// auto-resolving configured initiative/HP entries, pin sync) once the
    /// combatants are already built. Kept in MapRPG because it needs
    /// internal access to `BattleRoundModel`'s mutators.
    @MainActor @discardableResult func beginBattle(
        itemId: UUID,
        playerCombatants: [BattleCombatant],
        roomCombatants: [BattleCombatant],
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool
    @MainActor func startBattle(
        itemId: UUID,
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool
    @MainActor func endBattle(itemId: UUID) -> Bool
    @MainActor func setBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        value: Int?
    ) -> Bool
    @MainActor func adjustBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        amount: Int
    ) -> Bool
    @MainActor func setBattleInitiativeOrder(
        itemId: UUID,
        order: BattleInitiativeOrder
    ) -> Bool
    @MainActor func moveBattleEntries(from source: IndexSet, to destination: Int)
    @MainActor func activateBattleAttacker(itemId: UUID, combatantId: UUID) -> Bool
    @MainActor func nextBattleAttacker(itemId: UUID) -> Bool
    @MainActor func nextBattleRound(itemId: UUID) -> Bool
    @MainActor func addBattleCombatant(itemId: UUID, pinId: UUID) -> Bool
    @MainActor func addBattleRoll(
        itemId: UUID,
        combatantId: UUID,
        total: Int,
        expression: String?
    ) -> Bool
    @MainActor func selectBattleRollRecipient(
        itemId: UUID,
        combatantId: UUID
    ) -> Bool
    @MainActor func setBattleCombatantDead(
        itemId: UUID,
        combatantId: UUID,
        isDead: Bool
    ) -> Bool
    @MainActor func assignBattleCharacter(
        itemId: UUID,
        combatantId: UUID,
        characterId: UUID
    ) -> Bool
    @MainActor @discardableResult func setBattleValueEntry(
        itemId: UUID,
        combatantId: UUID,
        entryId: UUID?,
        kind: BattleValueKind
    ) -> Bool
    @MainActor func refreshBattleConfiguredValues(itemId: UUID)
    @MainActor func synchronizeBattleDefenders(itemId: UUID) -> Bool
    @MainActor func networkBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType?
    @MainActor func applyBattleRoundUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool
    @MainActor func resetBattleRound()
    @MainActor @discardableResult func updateMap(for itemId: UUID, with data: NetworkCodableDataType) -> Bool
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
        releaseBattleCharacters(includingPlayers: true)
        mapGameModel.reset()
    }
}

extension GameController: MapGameStorable {
    @MainActor
    var battleRoundModel: BattleRoundModel {
        mapGameModel.battleRoundModel
    }

    @MainActor
    var battleRoundSettings: BattleRoundSettingsModel {
        mapGameModel.battleRoundSettings
    }

    func mapAssetVersion(for itemId: UUID) async -> Int {
        if let generation = await mapGameModel.authoritativeGeneration(for: itemId) {
            return generation.assetVersion
        }
        if let metadata = await stablePackageMetadata(for: itemId) {
            return metadata.assetVersion
        }
        return await currentMapAssetVersion(for: itemId)
    }

    @MainActor
    func mapContentVersion(for itemId: UUID) -> Int {
        MapUpdatePayload(model: gameItem(for: itemId)).contentVersion
    }

    @MainActor
    func recordAuthoritativeMapGeneration(_ data: NetworkCodableDataType) {
        mapGameModel.recordAuthoritativeGeneration(data)
    }

    func shareMap(id: UUID) async -> NetworkCodableDataType {
        guard let metadata = await stablePackageMetadata(for: id) else {
            // A continuously edited map may not become stable within the
            // bounded retry window. This actor-isolated fallback is still one
            // internally consistent generation; a later asset change simply
            // makes receivers request the full package.
            return await currentMapReference(for: id)
        }
        return NetworkCodableDataType(
            id: id,
            type: .map,
            version: metadata.version,
            assetVersion: metadata.assetVersion,
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
        for _ in 0..<Self.maximumPackageExportAttempts {
            let capture = await mapContentCapture(for: itemId)
            guard let metadata = await stablePackageMetadata(for: itemId),
                  capture.core.version == metadata.version,
                  capture.core.contentVersion == metadata.contentVersion,
                  await packageCoreMetadata(for: itemId) == capture.core else {
                continue
            }
            return NetworkCodableDataType(
                id: itemId,
                type: .map,
                version: metadata.version,
                data: capture.data,
                assetVersion: metadata.assetVersion,
                contentVersion: metadata.contentVersion
            )
        }
        return await currentMapContentUpdate(for: itemId)
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
        mapGameModel.recordAuthoritativeGeneration(data)
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

    /// Reconciles the session roster into one live map as a single observable
    /// mutation. This is an explicit presentation-state transition rather than
    /// work performed while SwiftUI constructs the map view.
    @MainActor
    @discardableResult
    func synchronizePlayerPins(for itemId: UUID) -> Bool {
        guard let map = gameModel.itemData[itemId] as? MapModel else { return false }

        var reconciled = map.mapPins
        var indices: [UUID: Int] = [:]
        indices.reserveCapacity(reconciled.count + mapGameModel.playerPins.count)
        for index in reconciled.indices where indices[reconciled[index].id] == nil {
            indices[reconciled[index].id] = index
        }

        let resetTimestamp = Date.now.timeIntervalSince1970
        for playerPin in mapGameModel.playerPins {
            if let index = indices[playerPin.id] {
                guard playerPin.timeInterval > reconciled[index].timeInterval else { continue }
                reconciled[index] = playerPin
            } else {
                var resetPin = playerPin
                resetPin.location = .zero
                resetPin.timeInterval = resetTimestamp
                indices[resetPin.id] = reconciled.endIndex
                reconciled.append(resetPin)
            }
        }

        guard reconciled != map.mapPins else { return false }
        map.mapPins = reconciled
        return true
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

    /// Validates the current presentation generation and applies a player pin
    /// in one MainActor operation. Keeping these checks together prevents a
    /// same-id Map edit from slipping between validation and mutation.
    @MainActor
    func updatePinIfCurrentGeneration(
        itemId: UUID,
        data: NetworkCodableDataType,
        playerId: UUID
    ) -> Bool {
        let generation = networkGeneration(for: itemId)
        guard data.id == itemId,
              data.type == .map,
              gameModel.currentItemId == itemId,
              data.version == generation.version,
              data.assetVersion == generation.assetVersion,
              data.contentVersion == generation.contentVersion
        else { return false }

        return updatePin(itemId: itemId, data: data.data, playerId: playerId)
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
            let hasItem = await root.photoRoot.gameControllable.hasItem(id: photoId, version: 0)
            let hasFile: Bool
            if hasItem {
                hasFile = await root.photoRoot.gameControllable.hasLocalFileData(for: photoId)
            } else {
                hasFile = false
            }
            // A metadata-only Photo cannot render a pin. Route both missing
            // ownership and missing local bytes through the same Photo repair.
            guard !hasItem || !hasFile else { continue }
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
        mapGameModel.recordActivatedRoom(roomId, for: itemId)
        return true
    }

    /// Toggles the focused room on the authoritative live game map. Focusing
    /// one room clears every other room's focus through the domain behavior,
    /// and toggling the current room clears focus entirely.
    @MainActor
    func toggleRoomFocus(itemId: UUID, roomId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        guard let room = item.entries.first(where: { $0.id == roomId }) else { return false }
        item.focused(room)
        if item.entries.first(where: { $0.id == roomId })?.focused == true {
            mapGameModel.recordActivatedRoom(roomId, for: itemId)
        }
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
        guard updatePinState(itemId: itemId, pinId: pinId, mutation: { pin in
            pin.isHighlighted.toggle()
        }) else { return false }
        if battleRoundModel.isRunning, battleRoundModel.mapId == itemId {
            _ = synchronizeBattleDefenders(itemId: itemId)
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

    // MARK: - Battle round

    @MainActor
    func battleStartPins(itemId: UUID) -> (playerPins: [MapPinModel], roomPins: [MapPinModel])? {
        guard gameModel.currentItemId == itemId,
              let map = gameModel.itemData[itemId] as? MapModel else {
            return nil
        }

        let playerPins = map.mapPins.filter { $0.isPlayer && $0.characterId != nil }
        let roomId = mapGameModel.lastActivatedRoomId(for: itemId)
            ?? map.entries.first(where: \.focused)?.id
        let room = roomId.flatMap { selectedId in
            map.entries.first { $0.id == selectedId }
        }
        let roomPins = room.map { selectedRoom in
            map.mapPins.filter { !$0.isPlayer && selectedRoom.contains($0.location) }
        } ?? []

        guard !playerPins.isEmpty || !roomPins.isEmpty else { return nil }
        return (playerPins, roomPins)
    }

    @MainActor
    @discardableResult
    func beginBattle(
        itemId: UUID,
        playerCombatants: [BattleCombatant],
        roomCombatants: [BattleCombatant],
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool {
        guard let map = gameModel.itemData[itemId] as? MapModel else { return false }
        battleRoundModel.begin(
            mapId: itemId,
            players: playerCombatants,
            roomCombatants: roomCombatants,
            initiativeOrder: initiativeOrder
        )
        battleRoundSettings.initiativeOrder = initiativeOrder
        resolveBattleConfiguredValues()
        _ = battleRoundModel.synchronize(pins: map.mapPins)
        return true
    }

    @MainActor
    func startBattle(
        itemId: UUID,
        initiativeOrder: BattleInitiativeOrder
    ) -> Bool {
        guard let pins = battleStartPins(itemId: itemId) else { return false }

        let playerCombatants = pins.playerPins.map { pin in
            return BattleCombatant(
                pin: pin,
                sourceCharacterId: pin.characterId,
                // A player's Character is already the authoritative game
                // identity. Never clone it merely because a battle starts.
                gameCharacterId: pin.characterId,
                isPlayer: true
            )
        }
        let roomCombatants = pins.roomPins.compactMap { pin in
            makeBattleCombatant(itemId: itemId, pinId: pin.id)
        }

        clearBattleHighlights(itemId: itemId)
        return beginBattle(
            itemId: itemId,
            playerCombatants: playerCombatants,
            roomCombatants: roomCombatants,
            initiativeOrder: initiativeOrder
        )
    }

    @MainActor
    func makeBattleCombatant(itemId: UUID, pinId: UUID) -> BattleCombatant? {
        guard let map = gameModel.itemData[itemId] as? MapModel,
              let pinIndex = map.mapPins.firstIndex(where: { $0.id == pinId }) else {
            return nil
        }
        var pin = map.mapPins[pinIndex]
        let sourceCharacterId = pin.characterId
        let gameCharacterId: UUID?
        if pin.isPlayer {
            gameCharacterId = sourceCharacterId
        } else if let sourceCharacterId,
                  root.characterRoot.valueGameControllable.battleCharacterCopy(
                      for: sourceCharacterId
                  ) != nil {
            gameCharacterId = sourceCharacterId
        } else if let sourceCharacterId,
                  let copyId = root.characterRoot.valueGameControllable
                    .createBattleCharacterCopy(for: sourceCharacterId) {
            mapGameModel.registerBattleCharacterCopy(copyId)
            pin.characterId = copyId
            pin.timeInterval = max(
                Date.now.timeIntervalSince1970,
                pin.timeInterval.nextUp
            )
            map.mapPins[pinIndex] = pin
            gameCharacterId = copyId
        } else {
            gameCharacterId = nil
        }
        return BattleCombatant(
            pin: pin,
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId,
            isPlayer: pin.isPlayer
        )
    }

    @MainActor
    func clearBattleHighlights(itemId: UUID) {
        guard let map = gameModel.itemData[itemId] as? MapModel else { return }
        for index in map.mapPins.indices where map.mapPins[index].isHighlighted {
            map.mapPins[index].isHighlighted = false
            map.mapPins[index].timeInterval = max(
                Date.now.timeIntervalSince1970,
                map.mapPins[index].timeInterval.nextUp
            )
            if map.mapPins[index].isPlayer,
               let playerIndex = mapGameModel.playerPins.firstIndex(where: {
                   $0.id == map.mapPins[index].id
               }) {
                mapGameModel.playerPins[playerIndex] = map.mapPins[index]
            }
        }
    }

    @MainActor
    func endBattle(itemId: UUID) -> Bool {
        guard battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              let map = gameModel.itemData[itemId] as? MapModel else {
            return false
        }
        clearBattleHighlights(itemId: itemId)
        battleRoundModel.end()
        _ = battleRoundModel.synchronize(pins: map.mapPins)
        return true
    }

    @MainActor
    func setBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        value: Int?
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.setInitiative(value, for: combatantId)
    }

    @MainActor
    func adjustBattleInitiative(
        itemId: UUID,
        combatantId: UUID,
        amount: Int
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.adjustInitiative(by: amount, for: combatantId)
    }

    @MainActor
    func setBattleInitiativeOrder(
        itemId: UUID,
        order: BattleInitiativeOrder
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        battleRoundSettings.initiativeOrder = order
        return battleRoundModel.setInitiativeOrder(order)
    }

    @MainActor
    func moveBattleEntries(from source: IndexSet, to destination: Int) {
        battleRoundModel.moveEntries(from: source, to: destination)
    }

    @MainActor
    func activateBattleAttacker(itemId: UUID, combatantId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.activateAttacker(combatantId) else {
            return false
        }
        applyActiveBattleHighlights(itemId: itemId)
        return true
    }

    @MainActor
    func nextBattleAttacker(itemId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.nextAttacker() else {
            return false
        }
        applyActiveBattleHighlights(itemId: itemId)
        return true
    }

    @MainActor
    func nextBattleRound(itemId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.nextRound() else {
            return false
        }
        applyActiveBattleHighlights(itemId: itemId)
        return true
    }

    /// Adds a pin that was outside the initially focused room while the
    /// surprise round is still being prepared.
    @MainActor
    func addBattleCombatant(itemId: UUID, pinId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId,
              battleRoundModel.isPreparingSurprise,
              battleRoundModel.combatant(pinId: pinId) == nil,
              let combatant = makeBattleCombatant(itemId: itemId, pinId: pinId),
              battleRoundModel.addCombatant(combatant) else {
            return false
        }
        resolveBattleConfiguredValues(for: combatant.id)
        return true
    }

    @MainActor
    func addBattleRoll(
        itemId: UUID,
        combatantId: UUID,
        total: Int,
        expression: String?
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.addRoll(
            combatantId: combatantId,
            total: total,
            expression: expression
        )
    }

    @MainActor
    func selectBattleRollRecipient(itemId: UUID, combatantId: UUID) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.selectRollRecipient(combatantId)
    }

    @MainActor
    func setBattleCombatantDead(
        itemId: UUID,
        combatantId: UUID,
        isDead: Bool
    ) -> Bool {
        guard battleRoundModel.mapId == itemId,
              let combatant = battleRoundModel.combatant(id: combatantId),
              combatant.isDead != isDead,
              updatePinState(itemId: itemId, pinId: combatant.pinId, mutation: { pin in
                  pin.isDead = isDead
              }) else {
            return false
        }
        _ = synchronizeBattleDefenders(itemId: itemId)
        return true
    }

    /// Associates a Character with a battle token without touching the source
    /// database. Empty tokens receive an independent runtime copy. Existing
    /// player identities are reused, while non-player runtime identities are
    /// reused only when their copy is still present in Character game memory.
    @MainActor
    func assignBattleCharacter(
        itemId: UUID,
        combatantId: UUID,
        characterId: UUID
    ) -> Bool {
        guard battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              let combatant = battleRoundModel.combatant(id: combatantId),
              let map = gameModel.itemData[itemId] as? MapModel,
              let pinIndex = map.mapPins.firstIndex(where: { $0.id == combatant.pinId }) else {
            return false
        }

        let currentCharacterId = map.mapPins[pinIndex].characterId
        let sourceCharacterId: UUID
        let gameCharacterId: UUID

        if combatant.isPlayer, let currentCharacterId {
            // Player Characters are shared game identities and must not fork
            // into an isolated monster-style runtime copy.
            sourceCharacterId = currentCharacterId
            gameCharacterId = currentCharacterId
        } else if let currentCharacterId,
                  root.characterRoot.valueGameControllable.battleCharacterCopy(
                      for: currentCharacterId
                  ) != nil {
            // This token already owns a live runtime Character. Treat another
            // selection as a no-op so it cannot advance map state or fork the
            // association while the battle is running.
            return false
        } else {
            let source = currentCharacterId ?? characterId
            guard let copyId = root.characterRoot.valueGameControllable
                .createBattleCharacterCopy(for: source) else {
                return false
            }
            mapGameModel.registerBattleCharacterCopy(copyId)
            sourceCharacterId = source
            gameCharacterId = copyId
        }

        var updatedPin = map.mapPins[pinIndex]
        updatedPin.characterId = gameCharacterId
        updatedPin.timeInterval = max(
            Date.now.timeIntervalSince1970,
            updatedPin.timeInterval.nextUp
        )
        map.mapPins[pinIndex] = updatedPin
        if updatedPin.isPlayer,
           let playerIndex = mapGameModel.playerPins.firstIndex(where: { $0.id == updatedPin.id }) {
            mapGameModel.playerPins[playerIndex] = updatedPin
        }
        let changed = battleRoundModel.assignCharacter(
            combatantId: combatantId,
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId,
            pin: updatedPin
        )
        if changed {
            resolveBattleConfiguredValues(for: combatantId)
        }
        return changed
    }

    /// The orchestration (resolving the dropped/picked entry, remapping it to
    /// the combatant's own battle-copy entry by name, deriving an initiative
    /// value) lives in GameRPG's `BattleRoundController`, which is the only
    /// place that can reach `GameRoot`. This is the narrow primitive it
    /// composes to actually change `battleRoundModel`'s private state.
    @MainActor
    @discardableResult
    func setBattleValueEntry(
        itemId: UUID,
        combatantId: UUID,
        entryId: UUID?,
        kind: BattleValueKind
    ) -> Bool {
        guard battleRoundModel.mapId == itemId else { return false }
        return battleRoundModel.setValueEntry(entryId, kind: kind, for: combatantId)
    }

    @MainActor
    func refreshBattleConfiguredValues(itemId: UUID) {
        guard battleRoundModel.mapId == itemId else { return }
        resolveBattleConfiguredValues(remap: true)
    }

    @MainActor
    func synchronizeBattleDefenders(itemId: UUID) -> Bool {
        guard battleRoundModel.isRunning,
              battleRoundModel.mapId == itemId,
              let map = gameModel.itemData[itemId] as? MapModel else {
            return false
        }

        var repairedAttacker = false
        if let attackerPinId = battleRoundModel.activePinId,
           let attacker = map.mapPins.first(where: { $0.id == attackerPinId }),
           !attacker.isHighlighted {
            repairedAttacker = updatePinState(
                itemId: itemId,
                pinId: attackerPinId,
                mutation: { $0.isHighlighted = true }
            )
        }

        let additionalDefenderPinIds = map.mapPins.compactMap { pin -> UUID? in
            guard pin.isHighlighted,
                  pin.id != battleRoundModel.activePinId,
                  battleRoundModel.combatant(pinId: pin.id) == nil else {
                return nil
            }
            return pin.id
        }
        let additionalDefenders = additionalDefenderPinIds.compactMap { pinId in
            makeBattleCombatant(itemId: itemId, pinId: pinId)
        }
        let changed = battleRoundModel.synchronize(
            pins: map.mapPins,
            additionalDefenders: additionalDefenders
        )
        return repairedAttacker || changed
    }

    @MainActor
    func networkBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType? {
        guard battleRoundModel.mapId == itemId,
              let state = battleRoundModel.networkState() else {
            return nil
        }
        let generation = networkGeneration(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: generation.version,
            data: state.encodeData(),
            assetVersion: generation.assetVersion,
            contentVersion: generation.contentVersion
        )
    }

    @MainActor
    func applyBattleRoundUpdate(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        let generation = networkGeneration(for: itemId)
        guard data.id == itemId,
              data.type == .map,
              gameModel.currentItemId == itemId,
              data.version == generation.version,
              data.assetVersion == generation.assetVersion,
              data.contentVersion == generation.contentVersion,
              let state = BattleRoundNetworkState.decodeData(data.data),
              state.mapId == itemId else {
            return false
        }
        return battleRoundModel.applyRemoteState(state)
    }

    @MainActor
    func resetBattleRound() {
        releaseBattleCharacters(includingPlayers: true)
        mapGameModel.clearBattleCharacterCopies()
        battleRoundModel.reset()
    }

    @MainActor
    @discardableResult
    func updateMap(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        guard let mapData = data.data, let text = String(data: mapData, encoding: .utf8) else { return false }
        guard updateMap(for: itemId, with: text) else { return false }
        mapGameModel.recordAuthoritativeGeneration(data)
        return true
    }

    @MainActor
    func mapUpdateResult(for itemId: UUID) -> String {
        let model = gameItem(for: itemId)
        let first = model.entries.reduce("") { $0 + "\($1.id):\($1.isShown):\($1.focused)|" }
        return first + (JSONString.encode(value: [model.pointer] + model.mapPins) ?? "")
    }

    @MainActor
    func networkMapUpdate(for itemId: UUID) -> NetworkCodableDataType {
        let generation = networkGeneration(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: generation.version,
            data: mapUpdateResult(for: itemId).data(using: .utf8),
            assetVersion: generation.assetVersion,
            contentVersion: generation.contentVersion
        )
    }

    @MainActor
    func networkPin(itemId: UUID, position: MapPinModel) -> NetworkCodableDataType {
        let generation = networkGeneration(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: generation.version,
            data: position.encodeData(),
            assetVersion: generation.assetVersion,
            contentVersion: generation.contentVersion
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

    struct MapContentCapture: Sendable {
        let core: PackageCoreMetadata
        let data: Data?
    }

    @MainActor
    func networkGeneration(for itemId: UUID) -> MapGameModel.AuthoritativeGeneration {
        if let authoritative = mapGameModel.authoritativeGeneration(for: itemId) {
            return authoritative
        }
        let item = gameItem(for: itemId)
        return MapGameModel.AuthoritativeGeneration(
            version: item.version,
            assetVersion: currentMapAssetVersion(for: itemId),
            contentVersion: mapContentVersion(for: itemId)
        )
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
            let currentBackgroundPhotoVersion = await currentBackgroundPhotoVersion(
                for: after.backgroundPhotoId
            )
            guard before == after,
                  backgroundPhotoVersion == currentBackgroundPhotoVersion else {
                continue
            }
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
    func mapContentCapture(for itemId: UUID) -> MapContentCapture {
        let item = gameItem(for: itemId)
        let payload = MapUpdatePayload(model: item)
        return MapContentCapture(
            core: PackageCoreMetadata(
                version: item.version,
                contentVersion: payload.contentVersion,
                backgroundPhotoId: item.photoId
            ),
            data: payload.encodedData()
        )
    }

    @MainActor
    func currentMapReference(for itemId: UUID) -> NetworkCodableDataType {
        let item = gameItem(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: item.version,
            assetVersion: currentMapAssetVersion(for: itemId),
            contentVersion: MapUpdatePayload(model: item).contentVersion
        )
    }

    @MainActor
    func currentMapContentUpdate(for itemId: UUID) -> NetworkCodableDataType {
        let capture = mapContentCapture(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: capture.core.version,
            data: capture.data,
            assetVersion: currentMapAssetVersion(for: itemId),
            contentVersion: capture.core.contentVersion
        )
    }

    @MainActor
    func currentBackgroundPhotoVersion(for photoId: UUID?) -> Int? {
        guard let photoId else { return nil }
        let gamePhoto = root.photoRoot.gameControllable.gameModel.itemData[photoId] as? PhotoModel
        let persistentPhoto = root.photoRoot.itemControllable.itemSync(for: photoId) as? PhotoModel
        return (gamePhoto ?? persistentPhoto)?.version ?? -1
    }

    @MainActor
    func currentMapAssetVersion(for itemId: UUID) -> Int {
        let backgroundPhotoId = gameItem(for: itemId).photoId
        let backgroundPhotoVersion = currentBackgroundPhotoVersion(for: backgroundPhotoId)
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
    func resolveBattleConfiguredValues(
        for combatantId: UUID? = nil,
        remap: Bool = false
    ) {
        for combatant in battleRoundModel.combatants
        where combatantId == nil || combatant.id == combatantId {
            guard let gameCharacterId = combatant.gameCharacterId else { continue }

            if remap || combatant.initiativeEntryId == nil,
               let entry = root.characterRoot.valueGameControllable.gameEntry(
                   matchingAny: battleRoundSettings.initiativeNames,
                   characterId: gameCharacterId
               ) {
                _ = battleRoundModel.setValueEntry(
                    entry.id,
                    kind: .initiative,
                    for: combatant.id
                )
                // Automatic prefill is intentionally one-shot. A value typed
                // by the game master is never overwritten on later refreshes.
                if combatant.initiative == nil,
                   let value = root.characterRoot.valueGameControllable
                    .gameEntryDisplayValue(
                        characterId: gameCharacterId,
                        entryId: entry.id
                    ),
                   let initiative = battleInitiative(from: value) {
                    _ = battleRoundModel.setInitiative(
                        initiative,
                        for: combatant.id
                    )
                }
            }

            if remap || combatant.hitPointsEntryId == nil,
               let entry = root.characterRoot.valueGameControllable.gameEntry(
                   matchingAny: battleRoundSettings.hitPointsNames,
                   characterId: gameCharacterId
               ) {
                _ = battleRoundModel.setValueEntry(
                    entry.id,
                    kind: .hitPoints,
                    for: combatant.id
                )
            }
        }
    }

    func battleInitiative(from value: String) -> Int? {
        if let value = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(1, value)
        }
        guard let value = Double(
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        ), value.isFinite else {
            return nil
        }
        return max(1, Int(value))
    }

    @MainActor
    func releaseBattleCharacters(includingPlayers: Bool) {
        guard includingPlayers else { return }
        let ids = mapGameModel.battleCharacterCopyIds
        root.characterRoot.valueGameControllable.removeBattleCharacterCopies(ids)
    }

    @MainActor
    func applyActiveBattleHighlights(itemId: UUID) {
        guard let map = gameModel.itemData[itemId] as? MapModel,
              let entry = battleRoundModel.activeEntry,
              let attacker = battleRoundModel.attacker(for: entry) else {
            return
        }
        let highlightedPinIds = Set(
            [attacker.pinId] + battleRoundModel.defenders(for: entry).map(\.pinId)
        )
        for pin in map.mapPins where pin.isHighlighted != highlightedPinIds.contains(pin.id) {
            _ = updatePinState(itemId: itemId, pinId: pin.id) { updatedPin in
                updatedPin.isHighlighted = highlightedPinIds.contains(updatedPin.id)
            }
        }
        _ = battleRoundModel.synchronize(pins: map.mapPins)
    }

    @MainActor
    @discardableResult
    private func updateMap(for itemId: UUID, with result: String) -> Bool {
        let model = gameItem(for: itemId)
        var entries = model.entries
        guard let pinArrayStart = result.firstIndex(of: "[") else { return false }
        let entrySection = result[..<pinArrayStart]
        guard entrySection.isEmpty || entrySection.last == "|" else { return false }
        let pinText = String(result[pinArrayStart...])
        guard let mapPins: [MapPinModel] = JSONString.decode(text: pinText),
              let pointer = mapPins.first else {
            return false
        }

        for entryToken in entrySection.split(separator: "|") {
            let entryState = entryToken.split(separator: ":", omittingEmptySubsequences: false)
            guard entryState.count == 3,
                  let entryId = UUID(uuidString: String(entryState[0])),
                  let shown = Self.mapStateBool(entryState[1]),
                  let focused = Self.mapStateBool(entryState[2]),
                  let entryIndex = entries.firstIndex(where: { $0.id == entryId }) else {
                return false
            }
            entries[entryIndex].isShown = shown
            entries[entryIndex].focused = focused
        }

        let incoming = Array(mapPins.dropFirst())
        // Preserve only fields a player may optimistically change while
        // awaiting the authoritative round trip. Visibility, size, death,
        // and metadata always come from the game-master mapState.
        let mergedPins = incoming.map { incomingPin in
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

        model.pointer = pointer
        model.mapPins = mergedPins
        model.entries = entries
        return true
    }

    static func mapStateBool(_ value: Substring) -> Bool? {
        switch value {
        case "true": true
        case "false": false
        default: nil
        }
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
