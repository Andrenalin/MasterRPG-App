// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

extension GameController {
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

    /// Toggles a room using `MapModel`'s domain behavior. In particular, this
    /// preserves the hex-grid rule that revealing a hex also reveals rooms it
    /// intersects instead of duplicating that rule in a tabletop view.
    @MainActor
    func toggleRoom(itemId: UUID, roomId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        guard item.entries.contains(where: { $0.id == roomId }) else { return false }
        item.toggle(roomId)
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

}
