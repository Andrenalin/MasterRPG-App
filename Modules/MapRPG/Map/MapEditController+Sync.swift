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
        let baseline = editorModel.externalEntryIds
        // Merge each entry from the external map into the working copy,
        // skipping the entry currently being edited by the user.
        for externalEntry in newMap.entries {
            guard externalEntry.id != activeEntryId else { continue }
            if let index = copy.entries.firstIndex(where: { $0.id == externalEntry.id }) {
                copy.entries[index] = copy.entries[index].merge(externalEntry)
            } else if !baseline.contains(externalEntry.id) {
                // A room the external map held before and the working copy lacks was deleted
                // locally; only a room that is new there is added. See CODE_AUDIT_23 §5.11.
                copy.entries.append(externalEntry)
            }
        }
        // Remove entries that were deleted externally (except active). Entries the external map
        // never held are uncommitted local additions and stay.
        let externalIds = Set(newMap.entries.map(\.id))
        copy.entries.removeAll { entry in
            entry.id != activeEntryId && baseline.contains(entry.id) && !externalIds.contains(entry.id)
        }
        editorModel.externalEntryIds = externalIds
    }
}
