// @copyright André Trettin

import CoreGraphics
import Foundation

// Split out of MapEditController.swift — see CODE_AUDIT §9.13.

extension MapEditController {
    @MainActor
    func prepareTileWorkingCopy(from map: MapModel, editorModel: MapEditorSession) {
        prepareWorkingCopy(from: map, editorModel: editorModel)
        let displayConfig = editorModel.workingCopy?.displayConfig ?? map.displayConfig

        let tileEntry = MapEntryModel(
            id: displayConfig.id,
            name: String(localized: "Tile", bundle: .module),
            content: "",
            coordinates: displayConfig.tileCoordinates,
            isShown: true
        )
        editorModel.editEntries.resetEntries(mapId: map.id, entries: [tileEntry])
    }

    @MainActor
    func addTileCoordinate(_ coordinate: CGPoint, editorModel: MapEditorSession) {
        guard var tileEntry = editorModel.editEntries.entries.first else { return }
        tileEntry.coordinates.append(coordinate)
        editorModel.editEntries.setEntry(entry: tileEntry)
        syncTileCoordinates(
            tileEntry.coordinates,
            editorModel: editorModel,
            recordsHistory: true
        )
    }

    @MainActor
    func addTileCoordinateFromCanvas(_ coordinate: CGPoint, editorModel: MapEditorSession) {
        addTileCoordinate(coordinate, editorModel: editorModel)
    }

    @MainActor
    func syncTileCoordinates(
        _ coordinates: [CGPoint],
        editorModel: MapEditorSession,
        recordsHistory: Bool = false
    ) {
        editorModel.workingCopy?.displayConfig.tileCoordinates = coordinates
        if recordsHistory {
            recordMutation(
                String(localized: "Edit tile", bundle: .module),
                editorModel: editorModel
            )
        }
    }
}
