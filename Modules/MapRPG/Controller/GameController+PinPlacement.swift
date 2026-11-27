// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

// Player pin placement and handover, split out of GameController+Pins.swift. See CODE_AUDIT_29 §9.9.

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
        // The room the display cascades unplaced pins into. See CODE_AUDIT_29 §5.15.
        let placing = Set(toPlace)
        let room = MapPinPlacement.defaultRoom(in: map)
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
}
