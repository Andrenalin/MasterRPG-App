// @copyright André Trettin

import CoreRPG
import SwiftUI

enum MapEditorEvent {
    case pin(MapPinInteractionEvent)
    case toggleRoomVisibility(UUID)
    case toggleRoomFocus(UUID)
    case toggleHexGrid
    case canvasTap(CGPoint)
    case needleCoordinatesChanged(UUID)
    /// The pin photo popover was dismissed by the user (Escape, canvas tap).
    case dismissPinPhoto
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

    /// A retained MapEditor can survive replacement of the live game map with
    /// another model that has the same id. Editor actions intentionally keep
    /// using their working source map, while game actions must resolve the
    /// controller's current model at the moment the interaction commits.
    private var interactionMap: MapModel {
        switch session.mapMode {
        case .gameMaster, .player:
            root.gameController.gameItem(for: session.mapId)
        case .edit, .viewer:
            map
        }
    }

    func handle(_ event: MapEditorEvent) {
        switch event {
        case let .pin(event):
            handlePin(event)
        case let .toggleRoomVisibility(entryId):
            toggleRoomVisibility(entryId)
        case let .toggleRoomFocus(entryId):
            toggleRoomFocus(entryId)
        case .toggleHexGrid:
            toggleHexGrid()
        case let .canvasTap(location):
            handleCanvasTap(at: location)
        case let .needleCoordinatesChanged(entryId):
            handleNeedleCoordinatesChanged(entryId: entryId)
        case .dismissPinPhoto:
            dismissPinPhoto()
        }
    }

    /// Closes the photo popover. When the game master closes a photo they have shown to the
    /// players, it closes for everyone: the shared flag is turned off and broadcast.
    private func dismissPinPhoto() {
        guard let pinId = session.pins.photoPinId else { return }
        session.pins.setPhotoPinId(nil)
        guard session.mapMode == .gameMaster,
              session.pins.pinPointer(for: pinId)?.isZoom == true else { return }
        setSharedPinPhoto(pinId: pinId, shown: false)
    }

    /// Sends the photo flag change as a map state: the flag is set on one pin and cleared on all
    /// others, so every pin is synchronized back, not just this one. The players merge the state
    /// and open or close their popover.
    private func setSharedPinPhoto(pinId: UUID, shown: Bool) {
        guard session.mapMode == .gameMaster,
              root.gameController.setPinPhotoShown(itemId: session.mapId, pinId: pinId, shown: shown) else { return }
        session.pins.mapPins = interactionMap.mapPins
        session.broadcastMapEdit()
    }

    private func handleCanvasTap(at location: CGPoint) {
        dismissPinPhoto()
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
            session.updatePointer(location: location, map: interactionMap)
        }
    }

    private func toggleHexGrid() {
        guard session.mapMode == .gameMaster else { return }
        let liveMap = interactionMap
        _ = editController.toggleHexMap(for: liveMap)
        session.hexScale = liveMap.hexMapScale
        session.resetEntries(newEntries: liveMap.entries, map: liveMap, appliesFocus: false)
    }

    private func toggleRoomVisibility(_ entryId: UUID) {
        switch session.mapMode {
        case .edit:
            guard mapEditController.toggleRoomVisibility(
                entryId: entryId,
                editorModel: session
            ), let workingCopy = session.workingCopy else { return }
            synchronizeRooms(from: workingCopy)

        case .gameMaster:
            // Mutate the controller's current live map so the payload cannot
            // be built from a stale MapEditor reference, then broadcast
            // exactly one mapState — unless sharing is paused, like the 3D
            // table; turning sharing back on sends the full state.
            guard root.gameController.toggleRoom(
                itemId: session.mapId,
                roomId: entryId
            ) else { return }
            let liveMap = root.gameController.gameItem(for: session.mapId)
            synchronizeRooms(from: liveMap)
            session.broadcastMapEdit()

        case .player, .viewer:
            break
        }
    }

    private func synchronizeRooms(from source: MapModel) {
        // First-wins, not a trapping `uniqueKeysWithValues`: a peer or imported map can carry
        // two entries with one id. See CODE_AUDIT_21 §6.8.
        let updatedById = Dictionary(source.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in session.entries.entries {
            guard let updated = updatedById[entry.id] else { continue }
            session.entries.setEntry(entry: updated)
        }
    }

    private func toggleRoomFocus(_ entryId: UUID) {
        switch session.mapMode {
        case .edit:
            guard let entry = session.entries.entries.first(where: { $0.id == entryId }) else { return }
            let shouldFocus = !entry.focused
            for var candidate in session.entries.entries {
                candidate.focused = shouldFocus && candidate.id == entryId
                session.entries.setEntry(entry: candidate)
            }
            session.focusId = shouldFocus ? entryId : nil
            session.focusedMap()

            guard mapEditController.toggleRoomFocus(
                entryId: entryId,
                editorModel: session
            ), let workingCopy = session.workingCopy else { return }
            synchronizeRooms(from: workingCopy)

        case .gameMaster:
            // Focus is authoritative shared game state. Resolve the current
            // live map through GameController instead of mutating the map
            // captured when this router was installed; retained views can
            // otherwise publish a payload whose focus was never changed.
            guard root.gameController.toggleRoomFocus(
                itemId: session.mapId,
                roomId: entryId
            ) else { return }
            let liveMap = root.gameController.gameItem(for: session.mapId)
            synchronizeRooms(from: liveMap)
            session.focusId = liveMap.entries.first(where: \.focused)?.id
            session.focusedMap()
            session.broadcastFocusEdit()

        case .player, .viewer:
            // Room focus is a master-to-player viewport command. Players may
            // send their own pin state, but never room/mapState mutations.
            break
        }
    }

    private func handleNeedleCoordinatesChanged(entryId: UUID) {
        guard session.mapMode == .edit else { return }
        mapEditController.commitEntryCoordinates(
            entryId: entryId,
            editorModel: session
        )
    }

    private func handlePin(_ event: MapPinInteractionEvent) {
        switch event {
        case let .tap(pin, isPointer):
            handlePinSingleTap(pinId: pin.id, isPointer: isPointer)
        case .longPress:
            // Menu presentation is local view state owned by MapPinViewModel.
            break
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
        guard !isPointer else { return }
        switch session.mapMode {
        case .gameMaster:
            let addedCombatant = performGameMasterMutation(pinId: pinId) {
                root.gameController.addBattleCombatant(
                    itemId: session.mapId,
                    pinId: pinId
                )
            }
            guard !addedCombatant else { return }
            // Battle prep didn't consume the tap — a master's tap opens/closes
            // the local pin action menu instead of highlighting (that stays
            // player-only, below). Reuses the existing menu-toggle logic
            // (`MapPinViewModel.handleLongPress`, still driven by VoiceOver's
            // "Open Pin Actions" custom action too) now that long press is no
            // longer wired to a gesture.
            session.pins.pinNode(for: pinId)?.handleLongPress(context: .gameMaster)
        case .player:
            performPlayerMutation(pinId: pinId) {
                root.gameController.toggleHighlightPin(itemId: session.mapId, pinId: pinId, isGameMaster: false)
            }
        case .edit, .viewer:
            break
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
            // The game master's photo is shown to everyone: the map state carries it, and
            // clears the photo of any other pin. A hidden pin's photo stays on this device.
            guard let pin = session.pins.pinPointer(for: pinId) else { return }
            let show = session.pins.photoPinId != pinId
            if pin.isShown || pin.isZoom {
                // Not for a pin inside an unrevealed room. See CODE_AUDIT_24 §6.2.
                setSharedPinPhoto(pinId: pinId, shown: show && interactionMap.isPinVisibleToPlayers(pin))
            }
            session.pins.setPhotoPinId(show ? pinId : nil)
        case .player:
            // Players only see the photos of pins that are on the map for them.
            guard session.pins.pinPointer(for: pinId)?.isShown == true else { return }
            session.pins.togglePhoto(pinId: pinId)
        case .viewer:
            break
        }
    }

    private func handlePinMove(_ pin: MapPinModel, isPointer: Bool) {
        if isPointer {
            session.updatePointer(
                location: pin.location,
                map: interactionMap,
                withOutRelocation: true
            )
        } else if session.mapMode == .edit {
            mapEditController.updatePinMove(pin: pin, editorModel: session)
        } else if session.mapMode == .gameMaster {
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.movePin(
                    itemId: session.mapId,
                    pinId: pin.id,
                    location: pin.location
                )
            }
        } else if session.mapMode == .player,
                  interactionMap.mapPins.first(where: { $0.id == pin.id })?.isControlled(by: session.playerPinId) == true {
            performPlayerMutation(pinId: pin.id) {
                root.gameController.movePin(
                    itemId: session.mapId,
                    pinId: pin.id,
                    location: pin.location
                )
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
            // A hidden pin's character stays out of the room text players read.
            // See CODE_AUDIT_23 §5.11.
            if type == .character, pin.isShown, let characterId = pin.characterId {
                mapEditController.appendCharacterLinks(
                    [characterId],
                    to: session.entry(for: pin.location, in: map)?.id,
                    editorModel: session
                )
            }
            mapEditController.commitPinMutation(editorModel: session)
            return
        }
        guard context == .gameMaster else { return }

        switch type {
        case .dead:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.toggleDeadPin(itemId: session.mapId, pinId: pin.id)
            }
        case .visibility:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.togglePin(itemId: session.mapId, pinId: pin.id)
            }
        case .resize:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.resizePin(itemId: session.mapId, pinId: pin.id)
            }
        case .highlight:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.toggleHighlightPin(itemId: session.mapId, pinId: pin.id, isGameMaster: true)
            }
        case .battle:
            performGameMasterMutation(pinId: pin.id) {
                root.gameController.joinBattle(
                    itemId: session.mapId,
                    pinId: pin.id
                )
            }
        case .remove, .copy, .photo, .character:
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

    @discardableResult
    private func performGameMasterMutation(pinId: UUID, mutation: () -> Bool) -> Bool {
        guard session.mapMode == .gameMaster, mutation() else { return false }
        synchronizePinFromMap(pinId: pinId)
        session.broadcastMapEdit()
        return true
    }

    private func synchronizePinFromMap(pinId: UUID) {
        guard let updatedPin = interactionMap.mapPins.first(where: { $0.id == pinId }) else { return }
        session.pins.setPinPointer(updatedPin: updatedPin)
    }

    private func togglePointerVisibility(pinId: UUID) {
        let currentMap = interactionMap
        guard currentMap.pointer.id == pinId,
              root.gameController.togglePointer(itemId: session.mapId) else { return }
        session.pins.setPinPointer(updatedPin: currentMap.pointer)
        session.broadcastMapEdit()
    }
}
