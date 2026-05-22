// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct MapEditController {
    let editController: EditController
}

// MARK: - Working Copy Lifecycle

extension MapEditController {
    @MainActor
    func prepareWorkingCopy(from map: MapModel, editorModel: MapEditorModel) {
        editorModel.workingCopy = map.copy()
        editorModel.undoDepthAtOpen = editController.editorModel.undoManaged.undoDepth
    }

    @MainActor
    func commitChanges(editorModel: MapEditorModel, pinScale: CGFloat) {
        guard let copy = editorModel.workingCopy else { return }
        // Flush any in-progress entry edit into the working copy before saving
        for entry in editorModel.editEntries.entries {
            copy[entry.id] = entry
        }
        copy.pinScale = pinScale
        copy.mapPins = editorModel.pins.mapPins
        editController.save(
            updated: copy,
            message: String(localized: "map updated", bundle: .module).localizedString
        )
    }

    @MainActor
    func discardChanges(editorModel: MapEditorModel) {
        // Unwind any direct saves (MapEntryViewer gestures) that bypassed working copy
        let currentDepth = editController.editorModel.undoManaged.undoDepth
        let stepsToUndo = currentDepth - editorModel.undoDepthAtOpen
        for _ in 0..<max(0, stepsToUndo) {
            editController.undo()
        }
    }
}

// MARK: - External Sync (CloudKit / other windows)

extension MapEditController {
    @MainActor
    func mergeExternalPins(newMap: MapModel, editorModel: MapEditorModel) {
        guard let copy = editorModel.workingCopy else { return }
        // Merge external pin changes via CRDT; local drag state (in pins UI model) wins for
        // pins currently being positioned, since workingCopy will be saved on checkmark.
        let merged = copy.mapPins_.merged(other: newMap.mapPins_)
        copy.mapPins_ = merged
    }

    @MainActor
    func mergeExternalEntries(newMap: MapModel, editorModel: MapEditorModel) {
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

// MARK: - Pin Mutations (working copy only)

extension MapEditController {
    @MainActor
    func updatePinMove(pin: MapPinModel, editorModel: MapEditorModel) {
        editorModel.workingCopy?.setPinPointer(updatedPin: pin)
        editorModel.pins.setPinPointer(updatedPin: pin)
    }

    @MainActor
    func togglePinVisibility(pinId: UUID, editorModel: MapEditorModel) {
        guard var pin = editorModel.pins.pinPointer(for: pinId) else { return }
        pin.isShown.toggle()
        editorModel.workingCopy?.setPinPointer(updatedPin: pin)
        editorModel.pins.setPinPointer(updatedPin: pin)
    }
}

// MARK: - Entry / Map Navigation

extension MapEditController {
    @MainActor
    func changeMap(map: MapModel, currentEntryId: UUID?, editorModel: MapEditorModel) {
        if currentEntryId != editorModel.editEntries.entries.first?.id {
            // Flush current edit entry into working copy (not the store)
            for entry in editorModel.editEntries.entries {
                editorModel.workingCopy?[entry.id] = entry
            }

            // Load new entry from working copy into editEntries
            withAnimation(.bouncy) {
                if let currentEntryId {
                    let entry = editorModel.workingCopy?[currentEntryId] ?? map[currentEntryId]
                    editorModel.editEntries.resetEntries(mapId: map.id, entries: [entry])
                } else {
                    editorModel.editEntries.resetEntries(mapId: map.id, entries: [])
                }
            }
        }

        editorModel.isDragging = .nothing
        editorModel.isTapping = .nothing
        editorModel.editEntries.eaten = false
        editorModel.editEntries.addedNewNeedlePoint = nil

        if editorModel.appeared {
            editorModel.resetZoom()
        }
    }
}

// MARK: - Coordinate / Tap Handling

extension MapEditController {
    @MainActor
    func releaseAction(
        _ value: DragGesture.Value,
        map: MapModel,
        editorModel: MapEditorModel,
        hasEditableEntry: Bool
    ) {
        guard editorModel.isTapping != .nothing else { return }
        guard hasEditableEntry else { return }
        let roomPin = (value.location - editorModel.imageModel.offset) / editorModel.imageModel.scale
        guard editorModel.editEntries.eaten == false,
              editorModel.editEntries.addedNewNeedlePoint == nil else { return }

        editorModel.editEntries.addedNewNeedlePoint = roomPin

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                addCoordinateToWorkingCopy(map: map, editorModel: editorModel)
            }
        }
    }

    @MainActor
    func addCoordinateToWorkingCopy(map: MapModel, editorModel: MapEditorModel) {
        guard let point = editorModel.editEntries.addedNewNeedlePoint,
              var updatedEntry = editorModel.editEntries.entries.first else { return }

        editorModel.editEntries.addedNewNeedlePoint = nil
        updatedEntry.coordinates.append(point)
        editorModel.editEntries.setEntry(entry: updatedEntry)
        editorModel.workingCopy?[updatedEntry.id] = updatedEntry
    }
}

// MARK: - Drop Pin

extension MapEditController {
    @MainActor
    func dropPin(
        at point: CGPoint,
        map: MapModel,
        monsters: [ItemRowModel],
        editorModel: MapEditorModel
    ) {
        guard let copy = editorModel.workingCopy else { return }
        let location = (point - editorModel.imageModel.offset) / editorModel.imageModel.scale
        let entry = editorModel.entry(for: location, in: map)

        withAnimation(.bouncy) {
            editController.addMonsters(
                map: copy,
                entryId: entry?.id,
                location: location,
                monsters: monsters,
                number: 1
            )
        }
        // Sync pin UI model from updated working copy
        editorModel.pins.mapPins = copy.mapPins
    }
}

// MARK: - NeedleMapPin Operations (working copy only)

extension MapEditController {
    @MainActor
    func addNeedlePoint(at index: Int, entryId: UUID, entries: MapEntryViewerModel, map: MapModel) {
        var updatedEntry = entries.entry(entryId)
        let next = index + 1 < updatedEntry.coordinates.count ? index + 1 : 0
        var nextPoint = updatedEntry.coordinates[next]
        if next == 0 {
            nextPoint = nextPoint + CGPoint(x: 50, y: 50)
        } else {
            nextPoint = nextPoint - (nextPoint - updatedEntry.coordinates[index]) / 2
        }
        updatedEntry.coordinates.insert(nextPoint, at: next)
        entries.setEntry(entry: updatedEntry)

        // Find the MapEditorModel that owns this entries model to update workingCopy.
        // Since NeedleMapPin passes editEntries directly, we update via the entries model;
        // the caller (MapEditor) is responsible for passing the correct entries reference
        // that is backed by workingCopy (editEntries is already synced to workingCopy on commit).
    }

    @MainActor
    func removeNeedlePoint(at index: Int, entryId: UUID, entries: MapEntryViewerModel, map: MapModel) {
        entries.selectedNeedleIndex = nil
        var updatedEntry = entries.entry(entryId)
        guard index >= 0 && index < updatedEntry.coordinates.count else { return }
        updatedEntry.coordinates.remove(at: index)
        entries.setEntry(entry: updatedEntry)
    }

    @MainActor
    func updateNeedleCoordinate(entryId: UUID, entries: MapEntryViewerModel, map: MapModel) {
        // Coordinate already updated in entries via drag gesture — nothing more to do here.
        // The updated entry will be flushed into workingCopy on changeMap or commitChanges.
    }
}
