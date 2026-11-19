// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

extension GameController {
    @MainActor
    func setPlayerPin(for playerId: UUID, name: String, characterId: UUID) {
        let photoId = root.characterRoot.valueGameControllable.playerPinPhoto(for: characterId)

        if let index = mapGameModel.playerPins.firstIndex(where: { $0.id == playerId }) {
            mapGameModel.playerPins[index].name = name
            mapGameModel.playerPins[index].photoId = photoId
            mapGameModel.playerPins[index].characterId = characterId
            mapGameModel.playerPins[index].isPlayer = true
            // Keeps the devices the game master gave control of this pin;
            // `setPlayerPinControllers` is the only writer of that list.
            let controllers = mapGameModel.playerPins[index].players.filter { $0 != playerId }
            mapGameModel.playerPins[index].players = [playerId] + controllers
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
            // Only a pin that already is a player pin: a map's own pin with the same id (a
            // player-chosen companion id) is not turned into one. See CODE_AUDIT_24 §6.3.
            guard let index = map.mapPins.firstIndex(where: { $0.id == playerId && $0.isPlayer }) else { continue }
            Self.applyPlayerMetadata(from: playerPin, to: &map.mapPins[index])
        }
    }

    @MainActor
    func resetPlayerPins(for players: [PlayerGameModel]) {
        // A player pin never takes the id of a pin the map owns (a monster, a marker): a
        // companion's id is chosen by its player's device. See CODE_AUDIT_24 §6.3.
        var foreignPinIds = Set<UUID>()
        for itemId in gameModel.items {
            foreignPinIds.formUnion(gameItem(for: itemId).mapPins.lazy.filter { !$0.isPlayer }.map(\.id))
        }
        let players = players.filter { !foreignPinIds.contains($0.id) }
        let playerIds = Set(players.map(\.id))
        let handovers = pinHandovers(for: players)
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
        applyPinHandovers(handovers)
        keepBattleRosterInStepWithPlayerPins(handovers)
    }

    /// The pin of a Character that changes hands: a table player's pin leaves when a connected
    /// player joins with that Character (and the other way round), a companion's pin when its owner
    /// goes. Both pins stand for the same Character, so the new one takes over the old one's place
    /// and state instead of starting in the first room. See CODE_AUDIT_24 §5.1.
    private struct PinHandover {
        let oldPin: MapPinModel
        let newPinId: UUID
        /// The old pin as each live map holds it.
        let mapPins: [UUID: MapPinModel]
    }

    @MainActor
    private func pinHandovers(for players: [PlayerGameModel]) -> [PinHandover] {
        let playerIds = Set(players.map(\.id))
        var known = Set(mapGameModel.playerPins.map(\.id))
        for itemId in gameModel.items {
            known.formUnion(gameItem(for: itemId).mapPins.map(\.id))
        }
        var successors: [UUID: [UUID]] = [:]
        for player in players where !known.contains(player.id) {
            guard let characterId = player.characterId else { continue }
            successors[characterId, default: []].append(player.id)
        }
        guard !successors.isEmpty else { return [] }

        var oldPins: [UUID: MapPinModel] = [:]
        for pin in mapGameModel.playerPins where !playerIds.contains(pin.id) {
            oldPins[pin.id] = pin
        }
        for itemId in gameModel.items {
            for pin in gameItem(for: itemId).mapPins where pin.isPlayer && !playerIds.contains(pin.id) {
                oldPins[pin.id] = oldPins[pin.id] ?? pin
            }
        }
        var handovers: [PinHandover] = []
        for oldPin in oldPins.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let characterId = oldPin.characterId,
                  var candidates = successors[characterId], !candidates.isEmpty else { continue }
            let newPinId = candidates.removeFirst()
            successors[characterId] = candidates
            var onMaps: [UUID: MapPinModel] = [:]
            for itemId in gameModel.items {
                if let pin = gameItem(for: itemId).mapPins.first(where: { $0.id == oldPin.id }) {
                    onMaps[itemId] = pin
                }
            }
            handovers.append(PinHandover(oldPin: oldPin, newPinId: newPinId, mapPins: onMaps))
        }
        return handovers
    }

    /// Copies where the old pin stood, and its flags, onto the new pin of every map and the
    /// session cache. What the new pin owns itself (identity, name, photo, controllers) stays.
    @MainActor
    private func applyPinHandovers(_ handovers: [PinHandover]) {
        guard !handovers.isEmpty else { return }
        let now = Date.now.timeIntervalSince1970
        func carry(from old: MapPinModel, to pin: inout MapPinModel) {
            pin.location = old.location
            pin.mapId = old.mapId
            pin.size = old.size
            pin.isShown = old.isShown
            pin.isDead = old.isDead
            pin.isHighlighted = old.isHighlighted
            pin.healthPercent = old.healthPercent
            pin.timeInterval = now
        }
        for handover in handovers {
            if let index = mapGameModel.playerPins.firstIndex(where: { $0.id == handover.newPinId }) {
                carry(from: handover.oldPin, to: &mapGameModel.playerPins[index])
            }
            for (itemId, oldPin) in handover.mapPins {
                let map = gameItem(for: itemId)
                guard let index = map.mapPins.firstIndex(where: { $0.id == handover.newPinId }) else { continue }
                var pins = map.mapPins
                carry(from: oldPin, to: &pins[index])
                map.mapPins = pins
            }
        }
    }

    /// A running battle follows the pin handover (combatant, turn entry and defender links keep
    /// their ids; only the pin behind them changes) and drops a player combatant whose pin is gone
    /// without a successor, so no turn points to a missing pin.
    @MainActor
    private func keepBattleRosterInStepWithPlayerPins(_ handovers: [PinHandover]) {
        guard battleRoundModel.isRunning else { return }
        for handover in handovers {
            guard let pin = mapGameModel.playerPins.first(where: { $0.id == handover.newPinId }) else { continue }
            var carried = pin
            if let mapId = battleRoundModel.mapId, let onMap = gameModel.itemData[mapId] as? MapModel,
               let current = onMap.mapPins.first(where: { $0.id == handover.newPinId }) {
                carried = current
            }
            battleRoundModel.rekeyPin(from: handover.oldPin.id, to: carried)
        }
        battleRoundModel.dropPlayerCombatants(withoutPinIn: Set(mapGameModel.playerPins.map(\.id)))
    }

    /// Lists who may move each player pin, besides its own player: `controllers` maps a pin id
    /// to device ids (players or observers). Written to the session cache and every live map;
    /// the next map state carries it to every device. Returns whether any pin changed.
    @MainActor
    @discardableResult
    func setPlayerPinControllers(_ controllers: [UUID: [UUID]]) -> Bool {
        func players(for pinId: UUID) -> [UUID] {
            let extra = Set(controllers[pinId] ?? []).subtracting([pinId])
            return [pinId] + extra.sorted { $0.uuidString < $1.uuidString }
        }
        var changed = false
        for index in mapGameModel.playerPins.indices {
            let updated = players(for: mapGameModel.playerPins[index].id)
            guard mapGameModel.playerPins[index].players != updated else { continue }
            mapGameModel.playerPins[index].players = updated
            changed = true
        }
        let playerPinIds = Set(mapGameModel.playerPins.map(\.id))
        for itemId in gameModel.items {
            let map = gameItem(for: itemId)
            var pins = map.mapPins
            var mapChanged = false
            for index in pins.indices where pins[index].isPlayer && playerPinIds.contains(pins[index].id) {
                let updated = players(for: pins[index].id)
                guard pins[index].players != updated else { continue }
                pins[index].players = updated
                mapChanged = true
            }
            if mapChanged {
                map.mapPins = pins
                changed = true
            }
        }
        return changed
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

        let now = Date.now.timeIntervalSince1970
        for playerPin in mapGameModel.playerPins {
            if let index = indices[playerPin.id] {
                guard playerPin.timeInterval > reconciled[index].timeInterval else { continue }
                var updatedPin = playerPin
                // The shared copy carries the position of the map it was last moved on; it only
                // brings the position along for this map.
                if playerPin.mapId != itemId {
                    updatedPin.location = reconciled[index].location
                    updatedPin.mapId = reconciled[index].mapId
                }
                reconciled[index] = updatedPin
            } else {
                var resetPin = playerPin
                resetPin.location = .zero
                resetPin.mapId = nil
                resetPin.timeInterval = now
                indices[resetPin.id] = reconciled.endIndex
                reconciled.append(resetPin)
            }
        }

        placePlayerPinsInFirstRoom(&reconciled, indices: indices, on: map)

        guard reconciled != map.mapPins else { return false }
        map.mapPins = reconciled
        return true
    }

    /// Moves the session's player pins that do not stand on `map` yet to the first room (the center
    /// of the image when the map has none): a pin at
    /// (0, 0) never had a position, and a pin whose `mapId` is another map (or none) carries the
    /// position of that other map. A pin positioned on this map keeps it. The pins are placed
    /// like the display cascade does, so players who show the same pins as unpositioned see them
    /// where the game master has them now.
    @MainActor
    private func placePlayerPinsInFirstRoom(_ pins: inout [MapPinModel], indices: [UUID: Int], on map: MapModel) {
        let toPlace = mapGameModel.playerPins.compactMap { indices[$0.id] }.filter {
            pins[$0].location == .zero || pins[$0].mapId != map.id
        }
        guard !toPlace.isEmpty else { return }
        var placed = toPlace.map { index -> MapPinModel in
            var pin = pins[index]
            pin.location = .zero
            return pin
        }
        // A room the players can see wins, then a room with an area over a hex cell or a
        // text-only room.
        let placing = Set(toPlace)
        let room = map.entries.first { $0.isShown && !$0.isHexGrid && !$0.coordinates.isEmpty }
            ?? map.entries.first { $0.isShown && !$0.coordinates.isEmpty }
            ?? map.entries.first { !$0.isHexGrid && !$0.coordinates.isEmpty }
            ?? map.entries.first { !$0.coordinates.isEmpty }
        // Pins that already stand somewhere keep their spot: new ones go around them.
        let occupied = pins.enumerated()
            .filter { !placing.contains($0.offset) && $0.element.location != .zero }
            .map(\.element.location)
        if let room {
            placed = MapPinPlacement.cascade(pins: placed, in: room, pinScale: map.pinScale, occupied: occupied)
        } else {
            // A map without a room: the center of the image.
            placed = MapPinPlacement.centered(
                pins: placed,
                in: CGSize(width: map.width, height: map.height),
                pinScale: map.pinScale,
                occupied: occupied
            )
        }
        for (index, pin) in zip(toPlace, placed) {
            var updatedPin = pin
            updatedPin.mapId = map.id
            guard updatedPin != pins[index] else { continue }
            updatedPin.timeInterval = Self.bumpedTimeInterval(from: pins[index].timeInterval)
            pins[index] = updatedPin
        }
    }

    /// Largest pin coordinate magnitude accepted from a peer.
    static let maximumPinCoordinate: CGFloat = 1_000_000

    @MainActor
    func updatePin(itemId: UUID, data: Data?, playerId: UUID) -> Bool {
        guard let data, let incomingPin = MapPinModel.decodeData(of: data) else { return false }
        // A peer-supplied location is rebroadcast and projected by every device; reject
        // non-finite or absurd coordinates. See CODE_AUDIT_16 §5.7.
        guard incomingPin.location.x.isFinite, incomingPin.location.y.isFinite,
              abs(incomingPin.location.x) <= Self.maximumPinCoordinate,
              abs(incomingPin.location.y) <= Self.maximumPinCoordinate else {
            return false
        }
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

        // The pin's own player, or a device the game master gave control of it.
        let isControlledPlayerPin = currentPin.isControlled(by: playerId)
        guard isControlledPlayerPin || currentPin.isShown else { return false }

        var authorizedPin = currentPin
        if isControlledPlayerPin {
            authorizedPin.location = incomingPin.location
            authorizedPin.mapId = itemId
        }
        // Highlight is the only shared interaction permitted on a visible foreign pin. All
        // metadata and game-master state stay intact, `isPhotoShared` included: it means "the game
        // master shows this pin's photo to everyone" and only `setPinPhotoShown` writes it.
        authorizedPin.isHighlighted = incomingPin.isHighlighted

        guard authorizedPin.location != currentPin.location
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
        // See CODE_AUDIT §9.3 — shared generation-match guard, kept in sync
        // with `applyBattleRoundUpdate` in GameController+Battle.swift.
        guard isCurrentGeneration(data, for: itemId) else { return false }
        return updatePin(itemId: itemId, data: data.data, playerId: playerId)
    }

    /// Whether the map's background photo is usable on this device. A map
    /// without one is trivially complete.
    @MainActor func hasBackgroundImage(itemId: UUID) async -> Bool {
        guard let backgroundPhotoId = gameItem(for: itemId).photoId else { return true }
        return await hasPhotoImage(for: backgroundPhotoId)
    }

    @MainActor func awaitMapFiles(itemId: UUID) async -> Bool {
        let model = gameItem(for: itemId)
        // Hidden pins stay out: their photo must not be touched before the game master reveals them.
        var photoIds = model.mapPins.filter { model.isPinVisibleToPlayers($0) }.compactMap { $0.photoId }
        if let backgroundPhotoId = model.photoId { photoIds.insert(backgroundPhotoId, at: 0) }
        var seen: Set<UUID> = []
        let uniqueIds = photoIds.filter { seen.insert($0).inserted }
        let photos = root.photoRoot.gameControllable
        var present: [UUID] = []
        for photoId in uniqueIds where await photos.hasItem(id: photoId, version: 0) {
            // Start every download before waiting for the first one.
            _ = await photos.hasLocalFileData(for: photoId)
            present.append(photoId)
        }
        var allArrived = true
        for photoId in present {
            if await !photos.awaitLocalFileData(for: photoId) { allArrived = false }
        }
        return allArrived
    }

    @MainActor func missingMapImages(itemId: UUID) async -> [NetworkCodableDataType] {
        let model = gameItem(for: itemId)
        // A live map-state snapshot can introduce ordinary monster/character
        // pins as well as player-owned pins after the full map was imported.
        // Only their photos participate in this repair scan. The background is
        // part of the full map package and must stay on that transfer path.
        // Hidden pins are excluded outright — their photo must never be
        // proactively shared ahead of the GM revealing them. See CODE_AUDIT §6.1.
        let photoIds = model.mapPins.filter { model.isPinVisibleToPlayers($0) }.compactMap { $0.photoId }
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
            result.append(await root.photoRoot.gameControllable.share(id: photoId))
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
        if item.entries.first(where: { $0.id == roomId })?.isShown == true {
            mapGameModel.recordOpenedRoom(roomId, for: itemId)
        }
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
            mapGameModel.recordOpenedRoom(roomId, for: itemId)
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
            if isShown {
                mapGameModel.recordOpenedRoom(roomId, for: itemId)
            }
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
        // See CODE_AUDIT §9.4 — shared timestamp-bump idiom.
        item.pointer.timeInterval = Self.bumpedTimeInterval(from: item.pointer.timeInterval)
        return true
    }

    /// Shows or hides the shared pointer as an authoritative game-master action.
    @MainActor
    func togglePointer(itemId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        item.pointer.isShown.toggle()
        // See CODE_AUDIT §9.4 — shared timestamp-bump idiom.
        item.pointer.timeInterval = Self.bumpedTimeInterval(from: item.pointer.timeInterval)
        return true
    }

    /// Encodes the current pointer for the player-origin `.mapPin` route.
    @MainActor
    func networkPointer(itemId: UUID) -> NetworkCodableDataType? {
        let item = gameItem(for: itemId)
        return networkPin(itemId: itemId, position: item.pointer)
    }

    /// Moves the pointer to the map's centre and shows it: the game toolbar's "point" action on
    /// the 2D map and the 3D table. Returns whether anything changed. See CODE_AUDIT_19 §9.11.
    @MainActor
    func showPointerAtMapCenter(itemId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        let center = CGPoint(x: item.width / 2, y: item.height / 2)
        let moved = movePointer(itemId: itemId, location: center)
        let revealed = item.pointer.isShown ? false : togglePointer(itemId: itemId)
        return moved || revealed
    }

    @MainActor
    func photoAnchor(for itemId: UUID) -> CGPoint {
        let item = gameItem(for: itemId)
        if let roomId = mapGameModel.lastOpenedRoomId(for: itemId),
           let room = item.entries.first(where: { $0.id == roomId }),
           room.isShown,
           room.coordinates.bounds != nil {
            return room.center
        }
        return CGPoint(x: item.width / 2, y: item.height / 2)
    }

    /// The room a pin added from the game toolbar goes into: the focused room, else the room the
    /// game master opened last while it is still open. A hex cell is never taken for the last
    /// opened room. `nil` leaves the pin unplaced, which both map renderers then draw in the
    /// map's first entry (`MapPinPlacement.displayPins`).
    @MainActor
    func newPinRoomId(itemId: UUID, focusedRoomId: UUID?) -> UUID? {
        if let focusedRoomId { return focusedRoomId }
        let item = gameItem(for: itemId)
        guard let roomId = mapGameModel.lastOpenedRoomId(for: itemId),
              let room = item.entries.first(where: { $0.id == roomId }),
              room.isShown,
              !room.isHexGrid,
              room.coordinates.bounds != nil else { return nil }
        return room.id
    }

    /// Toggles a pin's visibility as the game master — the 3D-table
    /// equivalent of the 2D game-master double tap.
    @MainActor
    func togglePin(itemId: UUID, pinId: UUID) -> Bool {
        updatePinState(itemId: itemId, pinId: pinId) { pin in
            pin.isShown.toggle()
            // A hidden pin shows no photo: the shared flag would stay behind and the next share
            // of this pin would change nothing.
            if !pin.isShown {
                pin.isPhotoShared = false
            }
        }
    }

    /// Ends every shared pin photo of the game: on all live maps and the session's player
    /// pins. Called when another map is shown, so a flag left behind never counts as "already
    /// shared" the next time the game master shares that pin, and never pops up on a table
    /// that loads the map. Returns whether any pin changed.
    @MainActor
    @discardableResult
    func clearSharedPinPhotos() -> Bool {
        var changed = false
        for itemId in gameModel.items {
            let map = gameItem(for: itemId)
            for pin in map.mapPins where pin.isPhotoShared {
                changed = updatePinState(itemId: itemId, pinId: pin.id) { $0.isPhotoShared = false } || changed
            }
        }
        return changed
    }

    /// Shows or hides a pin's photo to everyone, as the game master — carried in mapState by the
    /// pin's `isPhotoShared` flag, whose name predates the photo popover. Only one photo is shown at a
    /// time: showing one turns the flag off on every other pin. Returns whether anything changed.
    @MainActor
    @discardableResult
    func setPinPhotoShown(itemId: UUID, pinId: UUID, shown: Bool) -> Bool {
        let item = gameItem(for: itemId)
        guard let pin = item.mapPins.first(where: { $0.id == pinId }) else { return false }
        var changed = false
        if shown {
            for other in item.mapPins where other.id != pinId && other.isPhotoShared {
                changed = updatePinState(itemId: itemId, pinId: other.id) { $0.isPhotoShared = false } || changed
            }
        }
        if pin.isPhotoShared != shown {
            changed = updatePinState(itemId: itemId, pinId: pinId) { $0.isPhotoShared = shown } || changed
        }
        return changed
    }

    /// Toggles the persistent death marker as an authoritative game-master
    /// action. Goes through `setPinDead`, so a combatant of a running battle
    /// gets the same bookkeeping as the battle card's own toggle.
    @MainActor
    func toggleDeadPin(itemId: UUID, pinId: UUID) -> Bool {
        guard let map = gameModel.itemData[itemId] as? MapModel,
              let pin = map.mapPins.first(where: { $0.id == pinId }) else {
            return false
        }
        return setPinDead(itemId: itemId, pinId: pinId, isDead: !pin.isDead)
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
    func toggleHighlightPin(itemId: UUID, pinId: UUID, isGameMaster: Bool) -> Bool {
        guard updatePinState(itemId: itemId, pinId: pinId, mutation: { pin in
            pin.isHighlighted.toggle()
        }) else { return false }
        if battleRoundModel.isRunning, battleRoundModel.mapId == itemId {
            _ = synchronizeBattleDefenders(itemId: itemId, isGameMaster: isGameMaster)
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
}
