// @copyright André Trettin

import CoreRPG
import SwiftUI

enum MapMode: Equatable, Sendable {
    case edit
    case gameMaster
    case player
    case viewer
}

struct MapEditorConfiguration: Equatable, Sendable {
    init(
        mode: MapMode,
        displayMode: MapDisplayMode,
        isTileEditor: Bool = false,
        playerPinId: UUID? = nil
    ) {
        self.mode = mode
        self.displayMode = displayMode
        self.isTileEditor = isTileEditor
        self.playerPinId = playerPinId
    }

    let mode: MapMode
    let displayMode: MapDisplayMode
    let isTileEditor: Bool
    let playerPinId: UUID?
}

struct MapEditorActions {
    init(
        sendMapUpdates: (@MainActor () -> Void)? = nil,
        sendPinUpdate: (@MainActor (UUID) -> Void)? = nil,
        focused: (@MainActor () -> Void)? = nil
    ) {
        self.sendMapUpdates = sendMapUpdates
        self.sendPinUpdate = sendPinUpdate
        self.focused = focused
    }

    let sendMapUpdates: (@MainActor () -> Void)?
    let sendPinUpdate: (@MainActor (UUID) -> Void)?
    let focused: (@MainActor () -> Void)?
}

@MainActor @Observable
final class MapEditorSelectionStore {
    private(set) var pinId: UUID?
    private(set) var needleId: UUID?

    func selectPin(_ id: UUID?) {
        pinId = id
        if id != nil { needleId = nil }
    }

    func selectNeedle(_ id: UUID?) {
        needleId = id
        if id != nil { pinId = nil }
    }

    func clear() {
        pinId = nil
        needleId = nil
    }
}

@MainActor @Observable
final class MapRoomStore {
    init(mapId: UUID, passiveEntries: [MapEntryModel]) {
        passive = MapEntryViewerModel(mapId: mapId, entries: passiveEntries)
        active = MapEntryViewerModel(mapId: mapId, entries: [])
    }

    let passive: MapEntryViewerModel
    let active: MapEntryViewerModel

    var needleDrag: MapNeedleInteractionModel { active.needleInteraction }

    func reset(mapId: UUID, passiveEntries: [MapEntryModel]) {
        passive.resetEntries(mapId: mapId, entries: passiveEntries)
        active.resetEntries(mapId: mapId, entries: [])
        active.needleInteraction.dragCoordinate = nil
        active.needleInteraction.dragPointId = nil
    }
}
