// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

// Pin updates and pin toggles, split out of GameController+Pins.swift. See CODE_AUDIT_29 §9.9.

extension GameController {
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
