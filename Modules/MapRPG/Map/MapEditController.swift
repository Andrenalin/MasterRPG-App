// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI
import CharacterRPG

struct MapEditController {
    let editController: EditController
}

// MARK: - Working Copy Lifecycle

extension MapEditController {
    @MainActor
    func prepareWorkingCopy(from map: MapModel, editorModel: MapEditorModel) {
        editorModel.workingCopy = map.copy()
        editorModel.undoDepthAtOpen = editController.editorModel.undoManaged.undoDepth
        editorModel.isHexMap = editorModel.workingCopy?.entries.contains(where: { $0.isHexGrid }) ?? false
    }

    @MainActor
    func commitChanges(editorModel: MapEditorModel) {
        guard let copy = editorModel.workingCopy else { return }
        // Flush any in-progress entry edit into the working copy before saving
        for entry in editorModel.editEntries.entries {
            copy[entry.id] = entry
        }
        copy.pinScale = editorModel.pinScale
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
            // Flush current edit entry into working copy and display entries
            for entry in editorModel.editEntries.entries {
                editorModel.workingCopy?[entry.id] = entry
                // Also update the display entries so the edited shape stays visible
                editorModel.entries.setEntry(entry: entry)
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
            addMonsters(entryId: entry?.id, location: location, monsters: monsters, number: 1, editorModel: editorModel)
        }
    }
}

// MARK: - Add Monsters (working copy only)

extension MapEditController {
    @MainActor
    func addMonsters(entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int, editorModel: MapEditorModel) {
        guard let copy = editorModel.workingCopy else { return }

        let pinCount = min(max(1, number), 25)
        var pins: [MapPinModel] = []
        for _ in 0..<pinCount {
            pins.append(contentsOf: monsters.map { monster in
                MapPinModel(
                    id: UUID(),
                    name: editController.root.characterRoot.linkControllable.name(for: monster.itemId),
                    color: .random,
                    photoId: editController.root.characterRoot.valueGameControllable.imageIds(for: monster.itemId).randomElement(),
                    location: location ?? .zero,
                    size: .normal,
                    isShown: true
                )
            })
        }

        if let entryId, location == nil {
            pins = calculatePinLocations(in: copy, for: pins, entryId: entryId)
        }

        for pin in pins {
            let index = copy.mapPins.count
            copy.mapPins.insert(pin, at: index)
        }

        editorModel.pins.mapPins = copy.mapPins
    }

    private func calculatePinLocations(in model: MapModel, for pins: [MapPinModel], entryId: UUID) -> [MapPinModel] {
        let entry = model[entryId]
        var leftCenter = CGPoint(x: entry.xOffset + entry.size.width / 4, y: entry.yOffset + entry.size.height / 2)
        return pins.map { pin in
            var updated = pin
            if updated.location == .zero {
                updated.location = leftCenter
                leftCenter = leftCenter + updated.size.size.width * model.pinScale + 5
            }
            return updated
        }
    }
}

// MARK: - Hex Map (working copy only)

extension MapEditController {
    @MainActor
    func isHexMap(editorModel: MapEditorModel) -> Bool {
        editorModel.workingCopy?.entries.contains(where: { $0.isHexGrid }) ?? false
    }

    @MainActor
    func toggleHexMap(editorModel: MapEditorModel) {
        guard let copy = editorModel.workingCopy else { return }
        if isHexMap(editorModel: editorModel) {
            copy.entries.removeAll { $0.isHexGrid }
            copy.hexMapScale = 0
        } else {
            let scale = initHexGridSize(model: copy, size: copy.hexMapScale)
            copy.hexMapScale = scale
            replaceHexGrid(entries: calculateGrid(for: scale, in: CGRect(origin: .zero, size: CGSize(width: copy.width, height: copy.height))), in: copy)
        }
        syncDisplayEntries(from: copy, editorModel: editorModel)
        editorModel.isHexMap = copy.entries.contains(where: { $0.isHexGrid })
        editorModel.hexScale = copy.hexMapScale
    }

    @MainActor
    func updateHexScale(_ scale: Double, editorModel: MapEditorModel) {
        guard let copy = editorModel.workingCopy, scale > 0, scale != copy.hexMapScale else { return }
        copy.hexMapScale = scale
        replaceHexGrid(entries: calculateGrid(for: scale, in: CGRect(origin: .zero, size: CGSize(width: copy.width, height: copy.height))), in: copy)
        syncDisplayEntries(from: copy, editorModel: editorModel)
        editorModel.isHexMap = copy.entries.contains(where: { $0.isHexGrid })
    }

    @MainActor
    private func syncDisplayEntries(from copy: MapModel, editorModel: MapEditorModel) {
        let activeEntryId = editorModel.editEntries.entries.first?.id
        let displayEntries = copy.entries.filter { $0.id != activeEntryId }
        editorModel.entries.resetEntries(mapId: copy.id, entries: displayEntries)
    }

    private func initHexGridSize(model: MapModel, size: Double) -> Double {
        guard size < 10 else { return size }
        let wScale = model.width / (12 * sqrt(3))
        let hScale = model.height / (12 * (3.0 / 2.0))
        return max(wScale, hScale)
    }

    private func replaceHexGrid(entries: [MapEntryModel], in model: MapModel) {
        model.entries.removeAll { $0.isHexGrid }
        model.entries.append(contentsOf: entries)
    }

    private func calculateGrid(for size: Double, in rect: CGRect) -> [MapEntryModel] {
        let hexWidth = sqrt(3) * size
        let hexHeight = 2 * size
        let columns = Int((rect.width + hexWidth / 2) / hexWidth) + 1
        let rows = Int((rect.height + size / 2) / (3 * size / 2)) + 1

        var hexa: [MapEntryModel] = []
        for row in 0..<rows {
            let offsetY = Double(row) * hexHeight - Double(row) * size / 2
            let offsetRow = (row % 2 != 0) ? -(hexWidth / 2) : 0
            for col in 0..<columns {
                let offsetX = Double(col) * hexWidth + offsetRow
                let coords = calculateHex(at: CGPoint(x: offsetX, y: offsetY), maxPoint: CGPoint(x: rect.width, y: rect.height), size: size)
                hexa.append(MapEntryModel(id: UUID(), name: "\(col) - \(row)", content: "", coordinates: coords, isHexGrid: true, displayState: DisplayStateMask.groupHidden.rawValue))
            }
        }
        return hexa
    }

    private func calculateHex(at offset: CGPoint, maxPoint: CGPoint, size: Double) -> [CGPoint] {
        let width = sqrt(3) * size
        let height = 2 * size
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, 0), maxPoint.x), y: min(max(p.y, 0), maxPoint.y))
        }
        return [
            clamp(CGPoint(x: offset.x,             y: offset.y)),
            clamp(CGPoint(x: offset.x + width / 2,  y: offset.y - height / 4)),
            clamp(CGPoint(x: offset.x + width,       y: offset.y)),
            clamp(CGPoint(x: offset.x + width,       y: offset.y + size)),
            clamp(CGPoint(x: offset.x + width / 2,  y: offset.y + 3 * height / 4)),
            clamp(CGPoint(x: offset.x,             y: offset.y + size)),
        ]
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
