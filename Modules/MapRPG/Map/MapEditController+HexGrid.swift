// @copyright André Trettin

import CoreGraphics
import Foundation

// Split out of MapEditController.swift — see CODE_AUDIT §9.13.
// `syncDisplayEntries` is internal rather than `private` so
// MapEditController+Rooms.swift and MapEditController+Boundary.swift can
// reach it too.

extension MapEditController {
    @MainActor
    func isHexMap(editorModel: MapEditorSession) -> Bool {
        editorModel.workingCopy?.entries.contains(where: { $0.isHexGrid }) ?? false
    }

    @MainActor
    func toggleHexMap(editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy else { return }
        if isHexMap(editorModel: editorModel) {
            copy.entries.removeAll { $0.isHexGrid }
            copy.hexMapScale = 0
        } else {
            let scale = MapHexGridGeometry.initialSize(for: copy, requestedSize: copy.hexMapScale)
            copy.hexMapScale = scale
            MapHexGridGeometry.replaceGrid(
                MapHexGridGeometry.grid(for: scale, in: CGRect(origin: .zero, size: CGSize(width: copy.width, height: copy.height))),
                in: copy
            )
        }
        syncDisplayEntries(from: copy, editorModel: editorModel)
        editorModel.isHexMap = copy.entries.contains(where: { $0.isHexGrid })
        editorModel.hexScale = copy.hexMapScale
        recordMutation(
            String(localized: "Toggle hex grid", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    func updateHexScale(_ scale: Double, editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy, scale > 0 else { return }
        // Never go below the size whose grid fits the cell cap: the slider snaps up to it
        // instead of the grid silently disappearing. See CODE_AUDIT_18 §5.6.
        let scale = MapHexGridGeometry.fittedSize(scale, width: copy.width, height: copy.height)
        guard scale != copy.hexMapScale else {
            editorModel.hexScale = scale
            return
        }
        copy.hexMapScale = scale
        editorModel.hexScale = scale
        MapHexGridGeometry.replaceGrid(
            MapHexGridGeometry.grid(for: scale, in: CGRect(origin: .zero, size: CGSize(width: copy.width, height: copy.height))),
            in: copy
        )
        syncDisplayEntries(from: copy, editorModel: editorModel)
        editorModel.isHexMap = copy.entries.contains(where: { $0.isHexGrid })
    }

    @MainActor
    func commitHexScale(editorModel: MapEditorSession) {
        recordMutation(
            String(localized: "Resize hex grid", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    func syncDisplayEntries(from copy: MapModel, editorModel: MapEditorSession) {
        let activeEntryId = editorModel.editEntries.entries.first?.id
        let displayEntries = copy.entries.filter { $0.id != activeEntryId }
        editorModel.entries.resetEntries(mapId: copy.id, entries: displayEntries)
    }
}
