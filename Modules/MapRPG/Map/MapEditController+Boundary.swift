// @copyright André Trettin

import CoreGraphics
import Foundation

// Split out of MapEditController.swift — see CODE_AUDIT §9.13.

extension MapEditController {
    @MainActor
    func updateMaxWidth(_ ratio: Double, editorModel: MapEditorSession) {
        rescaleEntries(editorModel: editorModel) { copy in
            editController.rescale(maxWidthRatio: ratio, in: copy)
        }
    }

    @MainActor
    func updateMaxHeight(_ ratio: Double, editorModel: MapEditorSession) {
        rescaleEntries(editorModel: editorModel) { copy in
            editController.rescale(maxHeightRatio: ratio, in: copy)
        }
    }

    @MainActor
    func commitBoundaryScale(editorModel: MapEditorSession) {
        recordMutation(
            String(localized: "Resize map areas", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    func updatePinScale(_ scale: CGFloat, editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy, copy.pinScale != scale else {
            recordMutation(
                String(localized: "Resize map pins", bundle: .module),
                editorModel: editorModel
            )
            return
        }
        copy.pinScale = scale
        editorModel.pinScale = scale
        recordMutation(
            String(localized: "Resize map pins", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    private func rescaleEntries(editorModel: MapEditorSession, using rescale: (MapModel) -> Void) {
        guard let copy = editorModel.workingCopy else { return }
        // Flush the in-progress entry edit so it is rescaled together with the others
        for entry in editorModel.editEntries.entries {
            copy[entry.id] = entry
        }
        // Flush pin state too — commitChanges takes pins from the UI model, not the copy
        copy.mapPins = editorModel.pins.mapPins
        rescale(copy)
        // Reload the active entry so it picks up its rescaled coordinates
        let rescaledActive = editorModel.editEntries.entries.map { copy[$0.id] }
        editorModel.editEntries.resetEntries(mapId: copy.id, entries: rescaledActive)
        editorModel.pins.mapPins = copy.mapPins
        syncDisplayEntries(from: copy, editorModel: editorModel)
    }
}
