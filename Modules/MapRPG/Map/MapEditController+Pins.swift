// @copyright André Trettin

import CoreGraphics
import CoreRPG
import SwiftUI

// Split out of MapEditController.swift — see CODE_AUDIT §9.13.

// MARK: - Pin Mutations (working copy only)

extension MapEditController {
    /// Records one completed pin action or drag. Pin leaf views keep transient
    /// drag state locally; this is the only point that updates the working copy.
    @MainActor @discardableResult
    func commitPinMutation(editorModel: MapEditorSession) -> Bool {
        editorModel.workingCopy?.mapPins = editorModel.pins.mapPins
        return recordMutation(
            String(localized: "Edit map pin", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    func updatePinMove(pin: MapPinModel, editorModel: MapEditorSession) {
        editorModel.pins.setPinPointer(updatedPin: pin)
        commitPinMutation(editorModel: editorModel)
    }

    @MainActor
    func togglePinVisibility(pinId: UUID, editorModel: MapEditorSession) {
        guard var pin = editorModel.pins.pinPointer(for: pinId) else { return }
        pin.isShown.toggle()
        editorModel.pins.setPinPointer(updatedPin: pin)
        commitPinMutation(editorModel: editorModel)
    }
}

// MARK: - Drop Pin

extension MapEditController {
    @MainActor
    func dropPin(
        at point: CGPoint,
        map: MapModel,
        monsters: [ItemRowModel],
        editorModel: MapEditorSession
    ) {
        guard editorModel.workingCopy != nil else { return }
        let location = editorModel.contentPoint(fromViewport: point)
        let entry = editorModel.entry(for: location, in: map)

        withAnimation(.bouncy) {
            addMonsters(entryId: entry?.id, location: location, monsters: monsters, number: 1, editorModel: editorModel)
        }
    }
}

// MARK: - Add Monsters (working copy only)

extension MapEditController {
    @MainActor
    func addMonsters(entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int, editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy else { return }

        var pins = MapPinPlacement.spawnPins(
            monsters: monsters,
            count: number,
            location: location,
            characterRoot: editController.root.characterRoot
        )

        // Without a selected room, pins added by selection go into the first room.
        let targetEntryId = entryId ?? (location == nil ? copy.entries.first(where: { !$0.isHexGrid })?.id : nil)
        if let targetEntryId, location == nil {
            pins = MapPinPlacement.cascade(pins: pins, in: copy[targetEntryId], pinScale: copy.pinScale)
        }

        editorModel.pins.mapPins = copy.mapPins + pins
        appendCharacterLinks(monsters.map(\.itemId), to: targetEntryId, editorModel: editorModel)
        commitPinMutation(editorModel: editorModel)
    }
}
