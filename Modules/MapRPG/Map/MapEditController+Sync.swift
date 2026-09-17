// @copyright André Trettin

import CoreRPG

// Split out of MapEditController.swift — see CODE_AUDIT §9.13.

extension MapEditController {
    @MainActor
    func mergeExternalPins(newMap: MapModel, editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy else { return }
        // Merge external pin changes via CRDT; local drag state (in pins UI model) wins for
        // pins currently being positioned, since workingCopy will be saved on checkmark.
        let merged = copy.mapPins_.merged(other: newMap.mapPins_)
        copy.mapPins_ = merged
        editorModel.pins.mapPins = copy.mapPins
    }

    @MainActor
    func mergeExternalEntries(newMap: MapModel, editorModel: MapEditorSession) {
        guard let copy = editorModel.workingCopy else { return }
        let activeEntryId = editorModel.editEntries.entries.first?.id
        // Merge each entry from the external map into the working copy,
        // skipping the entry currently being edited by the user.
        for externalEntry in newMap.entries {
            guard externalEntry.id != activeEntryId else { continue }
            if let index = copy.entries.firstIndex(where: { $0.id == externalEntry.id }) {
                copy.entries[index] = copy.entries[index].merge(externalEntry)
            } else {
                copy.entries.append(externalEntry)
            }
        }
        // Remove entries that no longer exist in the external map (except active)
        copy.entries.removeAll { entry in
            entry.id != activeEntryId && !newMap.entries.contains(where: { $0.id == entry.id })
        }
    }
}
