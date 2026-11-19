// @copyright André Trettin

import CoreGraphics
import CoreRPG
import PhotoRPG
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

        let characters = monsters.filter { $0.typeId != .photo }
        let photoIds = monsters.filter { $0.typeId == .photo }.map(\.itemId)

        withAnimation(.bouncy) {
            if !characters.isEmpty {
                addMonsters(entryId: entry?.id, location: location, monsters: characters, number: 1, editorModel: editorModel)
            }
            addPhotoPins(entryId: entry?.id, location: location, photoIds: photoIds, editorModel: editorModel)
        }
    }
}

// MARK: - Add Photo Pins (working copy only)

extension MapEditController {
    /// Adds one pin per photo, named after the photo and linked to no character. At `location`
    /// when it is given, otherwise cascaded in the selected room (or the first one) like
    /// monster pins.
    @MainActor
    func addPhotoPins(
        entryId: UUID? = nil,
        location: CGPoint? = nil,
        photoIds: [UUID],
        editorModel: MapEditorSession
    ) {
        guard let copy = editorModel.workingCopy, !photoIds.isEmpty else { return }

        let photoRoot = editController.root.photoRoot
        let photos = photoIds.map { photoId in
            (photoId: photoId, name: photoRoot.itemControllable.nameSync(itemId: photoId))
        }
        var pins = MapPinPlacement.spawnPhotoPins(photos: photos, location: location)

        let selectedEntryId = entryId ?? editController.editorModel.sheetEditorModel.entryId
        let targetEntryId = selectedEntryId ?? copy.entries.first(where: { !$0.isHexGrid })?.id
        if location == nil, let targetEntryId {
            pins = MapPinPlacement.cascade(
                pins: pins,
                in: copy[targetEntryId],
                pinScale: copy.pinScale,
                occupied: copy.mapPins.map(\.location)
            )
        }

        editorModel.pins.mapPins = copy.mapPins + pins
        commitPinMutation(editorModel: editorModel)
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
