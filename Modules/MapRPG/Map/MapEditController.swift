// @copyright André Trettin

import CoreRPG
import SwiftUI

// Split out of this file — see CODE_AUDIT §9.13:
// - MapEditController+Tile.swift: tile editor
// - MapEditController+Sync.swift: external (CloudKit/other window) merge
// - MapEditController+Pins.swift: pin mutations, drop pin, add monsters
// - MapEditController+Rooms.swift: room mutations, entry/map navigation, coordinate/tap handling
// - MapEditController+HexGrid.swift: hex map
// - MapEditController+Boundary.swift: entry boundary rescaling
//
// `synchronizeWorkingCopy`/`syncDisplayEntries` below are internal rather
// than `private` so those files can reach them — Swift's `private` only
// extends to same-file extensions.

struct MapEditController {
    let editController: EditController
}

// MARK: - Working Copy Lifecycle

extension MapEditController {
    @MainActor
    func prepareWorkingCopy(from map: MapModel, editorModel: MapEditorSession) {
        guard editorModel.workingCopy?.id != map.id else { return }
        editorModel.workingCopy = map.copy()
        editorModel.externalEntryIds = Set(map.entries.map(\.id))
        editorModel.undoDepthAtOpen = editController.editorModel.undoManaged.undoDepth
        if let copy = editorModel.workingCopy {
            editorModel.pinScale = copy.pinScale
            editorModel.hexScale = copy.hexMapScale
            editorModel.isHexMap = copy.entries.contains(where: { $0.isHexGrid })
            editorModel.pins.mapPins = copy.mapPins
            editorModel.maxWidthRatio = editController.maxWidthRatio(for: copy)
            editorModel.maxHeightRatio = editController.maxHeightRatio(for: copy)
            editorModel.isMapSizeOutOfSync = editController.isMapSizeOutOfSync(for: copy)
            editorModel.history.reset(
                to: MapEditorSnapshot(
                    map: copy,
                    activeEntryId: editController.editorModel.sheetEditorModel.entryId
                )
            )
        }
    }

    @MainActor
    func commitChanges(editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy else { return }
        synchronizeWorkingCopy(editorModel: editorModel)

        // The editor owns rooms, tile coordinates, pins, and map presentation
        // scales. Merge only those fields into the latest stored model so a
        // working copy opened before a photo/cache update cannot clear the
        // map's photo metadata when the editor is dismissed.
        let updated = editController.itemController.itemSync(for: copy.id)?.copy() ?? copy.copy()
        updated.entries = copy.entries
        updated.displayConfig = copy.displayConfig
        updated.pinScale = copy.pinScale
        updated.hexMapScale = copy.hexMapScale
        updated.mapPins = copy.mapPins
        // Map content stays in game memory while a game runs (user decision; CODE_AUDIT_Edit_Save §5.13).
        editController.save(
            updated: updated,
            message: String(localized: "map updated", bundle: .module),
            forceSave: false
        )
    }

    @MainActor
    func discardChanges(editorModel: MapEditorSession) {
        // Unwind any controller-side saves that occurred while this editor was open.
        let currentDepth = editController.editorModel.undoManaged.undoDepth
        let stepsToUndo = currentDepth - editorModel.undoDepthAtOpen
        for _ in 0..<max(0, stepsToUndo) {
            editController.undo()
        }
    }
}

// MARK: - Editor History

extension MapEditController {
    @MainActor
    @discardableResult
    func recordMutation(
        _ title: String,
        editorModel: MapEditorSession
    ) -> Bool {
        guard let copy = editorModel.workingCopy else { return false }
        synchronizeWorkingCopy(editorModel: editorModel)
        return editorModel.history.record(
            MapEditorSnapshot(
                map: copy,
                activeEntryId: editController.editorModel.sheetEditorModel.entryId
            ),
            title: title
        )
    }

    @MainActor
    @discardableResult
    func undo(editorModel: MapEditorSession) -> Bool {
        guard let snapshot = editorModel.history.undo() else { return false }
        restore(snapshot, editorModel: editorModel)
        return true
    }

    @MainActor
    @discardableResult
    func redo(editorModel: MapEditorSession) -> Bool {
        guard let snapshot = editorModel.history.redo() else { return false }
        restore(snapshot, editorModel: editorModel)
        return true
    }

    @MainActor
    func synchronizeWorkingCopy(editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy else { return }
        if editorModel.configuration.isTileEditor {
            if let tileEntry = editorModel.editEntries.entries.first {
                copy.displayConfig.tileCoordinates = tileEntry.coordinates
            }
        } else {
            for entry in editorModel.editEntries.entries {
                copy[entry.id] = entry
            }
        }
        copy.mapPins = editorModel.pins.mapPins
        copy.pinScale = editorModel.pinScale
        copy.hexMapScale = editorModel.hexScale
    }

    @MainActor
    private func restore(
        _ snapshot: MapEditorSnapshot,
        editorModel: MapEditorSession
    ) {
        let copy = snapshot.map.copy()
        editorModel.workingCopy = copy
        editorModel.pinScale = copy.pinScale
        editorModel.hexScale = copy.hexMapScale
        editorModel.isHexMap = copy.entries.contains(where: { $0.isHexGrid })
        editorModel.maxWidthRatio = editController.maxWidthRatio(for: copy)
        editorModel.maxHeightRatio = editController.maxHeightRatio(for: copy)
        editorModel.isMapSizeOutOfSync = editController.isMapSizeOutOfSync(for: copy)
        editorModel.pins.mapPins = copy.mapPins
        editorModel.clearSelections()

        if editorModel.configuration.isTileEditor {
            let tileEntry = MapEntryModel(
                id: copy.displayConfig.id,
                name: String(localized: "Tile", bundle: .module),
                content: "",
                coordinates: copy.displayConfig.tileCoordinates,
                isShown: true
            )
            editorModel.editEntries.resetEntries(mapId: copy.id, entries: [tileEntry])
            editorModel.entries.resetEntries(mapId: copy.id, entries: [])
            return
        }

        let activeEntryId = snapshot.activeEntryId.flatMap { entryId in
            copy.entries.contains(where: { $0.id == entryId && !$0.isHexGrid })
                ? entryId
                : nil
        }
        let activeEntries = activeEntryId.map { [copy[$0]] } ?? []
        editorModel.editEntries.resetEntries(mapId: copy.id, entries: activeEntries)
        syncDisplayEntries(from: copy, editorModel: editorModel)
        editorModel.focusId = copy.entries.first(where: \.focused)?.id
        editController.editorModel.sheetEditorModel.entryId = activeEntryId
    }
}
