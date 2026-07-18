// @copyright André Trettin

import CoreRPG
import SwiftUI

enum MapEditorEvent {
    case pin(MapPinInteractionEvent)
    case toggleRoomVisibility(UUID)
    case toggleRoomFocus(UUID)
    case canvasTap(CGPoint)
    case needleCoordinatesChanged(UUID)
}

@MainActor
final class MapEditorActionRouter {
    init(
        session: MapEditorSession,
        editController: EditController,
        mapEditController: MapEditController,
        map: MapModel,
        root: MapRootModel
    ) {
        self.session = session
        self.editController = editController
        self.mapEditController = mapEditController
        self.map = map
        self.root = root
    }

    private unowned let session: MapEditorSession
    private let editController: EditController
    private let mapEditController: MapEditController
    private let map: MapModel
    private let root: MapRootModel

    func handle(_ event: MapEditorEvent) {
        switch event {
        case let .pin(event):
            handlePin(event)
        case let .toggleRoomVisibility(entryId):
            toggleRoomVisibility(entryId)
        case let .toggleRoomFocus(entryId):
            toggleRoomFocus(entryId)
        case let .canvasTap(location):
            handleCanvasTap(at: location)
        case let .needleCoordinatesChanged(entryId):
            handleNeedleCoordinatesChanged(entryId: entryId)
        }
    }

    private func handleCanvasTap(at location: CGPoint) {
        session.clearSelections()

        if session.configuration.isTileEditor {
            let coordinate = session.contentPoint(fromViewport: location)
            mapEditController.addTileCoordinateFromCanvas(coordinate, editorModel: session)
        } else if session.mapMode == .edit {
            mapEditController.releaseAction(
                at: location,
                map: map,
                editorModel: session,
                hasEditableEntry: !session.editEntries.entries.isEmpty
            )
        } else if session.mapMode != .viewer {
            session.updatePointer(location: location, map: map)
        }
    }

    private func toggleRoomVisibility(_ entryId: UUID) {
        switch session.mapMode {
        case .edit:
            guard let mapModel = editController.editModel(for: map.id) else { return }
            mapModel.toggle(entryId)
            synchronizeVisibleRooms(from: mapModel)
            editController.save(
                updated: mapModel,
                message: String(localized: "update entry", bundle: .module).localizedString
            )

        case .gameMaster:
            // A room toggle is an authoritative game command, not an
            // optional continuous-streaming update. Mutate the controller's
            // current live map so the payload cannot be built from a stale
            // MapEditor reference, then broadcast exactly one mapState.
            guard root.gameController.toggleRoom(
                itemId: session.mapId,
                roomId: entryId
            ) else { return }
            let liveMap = root.gameController.gameItem(for: session.mapId)
            synchronizeVisibleRooms(from: liveMap)
            session.actions.sendMapUpdates?()

        case .player, .viewer:
            break
        }
    }

    private func synchronizeVisibleRooms(from source: MapModel) {
        let updatedById = Dictionary(uniqueKeysWithValues: source.entries.map { ($0.id, $0) })
        for entry in session.entries.entries {
            guard let updated = updatedById[entry.id] else { continue }
            session.entries.setEntry(entry: updated)
        }
    }

    private func toggleRoomFocus(_ entryId: UUID) {
        guard let entry = session.entries.entries.first(where: { $0.id == entryId }) else { return }
        let shouldFocus = !entry.focused
        for var candidate in session.entries.entries {
            candidate.focused = shouldFocus && candidate.id == entryId
            session.entries.setEntry(entry: candidate)
        }
        session.focusId = shouldFocus ? entryId : nil
        session.focusedMap()

        if session.mapMode == .edit {
            guard let mapModel = editController.editModel(for: map.id) else { return }
            mapModel.focused(entry)
            editController.save(
                updated: mapModel,
                message: String(localized: "focus entry", bundle: .module).localizedString
            )
        } else {
            map.focused(entry)
            session.actions.focused?()
        }
    }

    private func handleNeedleCoordinatesChanged(entryId: UUID) {
        guard session.configuration.isTileEditor else { return }
        mapEditController.syncTileCoordinates(
            session.editEntries.entry(entryId).coordinates,
            editorModel: session
        )
    }

    private func handlePin(_ event: MapPinInteractionEvent) {
        switch event {
        case let .tap(pin, isPointer):
            handlePinSingleTap(pinId: pin.id, isPointer: isPointer)
        case let .doubleTap(pin, isPointer):
            handlePinDoubleTap(pinId: pin.id, isPointer: isPointer)
        case .beginMove:
            break
        case let .move(pin, isPointer):
            handlePinMove(pin, isPointer: isPointer)
        case let .action(type, pin, isPointer, context):
            handlePinAction(type, pin: pin, isPointer: isPointer, context: context)
        }
    }

    private func handlePinSingleTap(pinId: UUID, isPointer: Bool) {
        guard session.mapMode == .player, !isPointer else { return }
        performPlayerMutation(pinId: pinId) {
            root.gameController.toggleHighlightPin(itemId: map.id, pinId: pinId)
        }
    }

    private func handlePinDoubleTap(pinId: UUID, isPointer: Bool) {
        if isPointer {
            if session.mapMode == .edit {
                mapEditController.togglePinVisibility(pinId: pinId, editorModel: session)
            } else if session.mapMode == .gameMaster {
                togglePointerVisibility(pinId: pinId)
            }
            return
        }

        switch session.mapMode {
        case .edit:
            mapEditController.togglePinVisibility(pinId: pinId, editorModel: session)
        case .gameMaster:
            performGameMasterMutation(pinId: pinId) {
                root.gameController.zoomPin(itemId: map.id, pinId: pinId)
            }
        case .player:
            performPlayerMutation(pinId: pinId) {
                root.gameController.zoomPin(itemId: map.id, pinId: pinId)
            }
        case .viewer:
            break
        }
    }

    private func handlePinMove(_ pin: MapPinModel, isPointer: Bool) {
        if isPointer {
            session.updatePointer(location: pin.location, map: map, withOutRelocation: true)
        } else if session.mapMode == .edit {
            mapEditController.updatePinMove(pin: pin, editorModel: session)
        } else if session.mapMode == .gameMaster {
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.movePin(itemId: map.id, pinId: pin.id, location: pin.location)
            }
        } else if session.mapMode == .player, pin.id == session.playerPinId {
            performPlayerMutation(pinId: pin.id) {
                root.gameController.movePin(itemId: map.id, pinId: pin.id, location: pin.location)
            }
        }
    }

    private func handlePinAction(
        _ type: MapPinButtonType,
        pin: MapPinModel,
        isPointer: Bool,
        context: MapPinActionContext
    ) {
        guard !isPointer else { return }
        if context == .editor {
            mapEditController.commitPinMutation(editorModel: session)
            return
        }
        guard context == .gameMaster else { return }

        switch type {
        case .dead:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.toggleDeadPin(itemId: map.id, pinId: pin.id)
            }
        case .visibility:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.togglePin(itemId: map.id, pinId: pin.id)
            }
        case .resize:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.resizePin(itemId: map.id, pinId: pin.id)
            }
        case .zoom:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.zoomPin(itemId: map.id, pinId: pin.id)
            }
        case .remove, .copy, .photo:
            break
        }
    }

    private func performPlayerMutation(pinId: UUID, mutation: () -> Bool) {
        guard session.mapMode == .player,
              session.pins.pinPointer(for: pinId)?.isShown == true,
              mutation() else { return }
        synchronizePinFromMap(pinId: pinId)
        session.actions.sendPinUpdate?(pinId)
    }

    private func performGameMasterMutation(pinId: UUID, mutation: () -> Bool) {
        guard session.mapMode == .gameMaster, mutation() else { return }
        synchronizePinFromMap(pinId: pinId)
        if session.isStreaming {
            session.actions.sendMapUpdates?()
        }
    }

    private func synchronizePinFromMap(pinId: UUID) {
        guard let updatedPin = map.mapPins.first(where: { $0.id == pinId }) else { return }
        session.pins.setPinPointer(updatedPin: updatedPin)
    }

    private func togglePointerVisibility(pinId: UUID) {
        guard var pointer = session.pins.pinPointer(for: pinId) else { return }
        pointer.isShown.toggle()
        pointer.timeInterval = max(Date.now.timeIntervalSince1970, pointer.timeInterval.nextUp)
        session.pins.setPinPointer(updatedPin: pointer)
        map.setPinPointer(updatedPin: pointer)
        if session.isStreaming {
            session.actions.sendMapUpdates?()
        }
    }
}
