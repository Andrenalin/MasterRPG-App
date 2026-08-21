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
