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
    func prepareWorkingCopy(from map: MapModel, editorModel: MapEditorSession) {
        guard editorModel.workingCopy?.id != map.id else { return }
        editorModel.workingCopy = map.copy()
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
        editController.save(
            updated: updated,
            message: String(localized: "map updated", bundle: .module).localizedString
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
    private func synchronizeWorkingCopy(editorModel: MapEditorSession) {
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

// MARK: - Tile Editor

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

// MARK: - External Sync (CloudKit / other windows)

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

// MARK: - Room Mutations

extension MapEditController {
    @MainActor
    @discardableResult
    func toggleRoomVisibility(
        entryId: UUID,
        editorModel: MapEditorSession
    ) -> Bool {
        guard let copy = editorModel.workingCopy,
              copy.entries.contains(where: { $0.id == entryId }) else {
            return false
        }
        synchronizeWorkingCopy(editorModel: editorModel)
        copy.toggle(entryId)
        synchronizeRoomPresentation(from: copy, editorModel: editorModel)
        return recordMutation(
            String(localized: "Toggle map area visibility", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    @discardableResult
    func toggleRoomFocus(
        entryId: UUID,
        editorModel: MapEditorSession
    ) -> Bool {
        guard let copy = editorModel.workingCopy,
              let entry = copy.entries.first(where: { $0.id == entryId }) else {
            return false
        }
        synchronizeWorkingCopy(editorModel: editorModel)
        copy.focused(entry)
        synchronizeRoomPresentation(from: copy, editorModel: editorModel)
        editorModel.focusId = copy.entries.first(where: \.focused)?.id
        return recordMutation(
            String(localized: "Focus map area", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    func commitEntryCoordinates(
        entryId: UUID,
        editorModel: MapEditorSession
    ) {
        guard let copy = editorModel.workingCopy else { return }
        if editorModel.configuration.isTileEditor {
            let coordinates = editorModel.editEntries.entry(entryId).coordinates
            copy.displayConfig.tileCoordinates = coordinates
        } else {
            copy[entryId] = editorModel.editEntries.entry(entryId)
        }
        recordMutation(
            String(localized: "Edit map area", bundle: .module),
            editorModel: editorModel
        )
    }

    @MainActor
    func addEntry(editorModel: MapEditorSession) -> UUID? {
        guard let copy = editorModel.workingCopy else { return nil }
        synchronizeWorkingCopy(editorModel: editorModel)
        let entry = MapEntryModel.empty
        copy.entries.append(entry)
        editController.editorModel.sheetEditorModel.entryId = entry.id
        editorModel.editEntries.resetEntries(mapId: copy.id, entries: [entry])
        synchronizeRoomPresentation(from: copy, editorModel: editorModel)
        recordMutation(
            String(localized: "Add map area", bundle: .module),
            editorModel: editorModel
        )
        return entry.id
    }

    @MainActor
    private func synchronizeRoomPresentation(
        from copy: MapModel,
        editorModel: MapEditorSession
    ) {
        let activeEntryId = editorModel.editEntries.entries.first?.id
        if let activeEntryId,
           let activeEntry = copy.entries.first(where: { $0.id == activeEntryId }) {
            editorModel.editEntries.resetEntries(mapId: copy.id, entries: [activeEntry])
        }
        syncDisplayEntries(from: copy, editorModel: editorModel)
    }
}

// MARK: - Entry / Map Navigation

extension MapEditController {
    @MainActor
    func changeMap(map: MapModel, currentEntryId: UUID?, editorModel: MapEditorSession) {
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
    }
}

// MARK: - Coordinate / Tap Handling
extension MapEditController {
    @MainActor
    func releaseAction(
        at location: CGPoint,
        map: MapModel,
        editorModel: MapEditorSession,
        hasEditableEntry: Bool
    ) {
        guard hasEditableEntry else { return }
        let point = editorModel.contentPoint(fromViewport: location)
        guard var updatedEntry = editorModel.editEntries.entries.first else { return }
        updatedEntry.coordinates.append(point)
        editorModel.editEntries.setEntry(entry: updatedEntry)
        editorModel.workingCopy?[updatedEntry.id] = updatedEntry
        recordMutation(
            String(localized: "Add map area point", bundle: .module),
            editorModel: editorModel
        )
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

        let pinCount = min(max(1, number), 25)
        var pins: [MapPinModel] = []
        for _ in 0..<pinCount {
            pins.append(contentsOf: monsters.map { monster in
                MapPinModel(
                    id: UUID(),
                    name: editController.root.characterRoot.linkControllable.name(for: monster.itemId),
                    color: .random,
                    photoId: editController.root.characterRoot.valueGameControllable.imageIds(for: monster.itemId).randomElement(),
                    characterId: monster.itemId,
                    location: location ?? .zero,
                    size: .normal,
                    isShown: true
                )
            })
        }

        if let entryId, location == nil {
            pins = calculatePinLocations(in: copy, for: pins, entryId: entryId)
        }

        editorModel.pins.mapPins = copy.mapPins + pins
        commitPinMutation(editorModel: editorModel)
    }

    @MainActor private func calculatePinLocations(in model: MapModel, for pins: [MapPinModel], entryId: UUID) -> [MapPinModel] {
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
            let scale = initHexGridSize(model: copy, size: copy.hexMapScale)
            copy.hexMapScale = scale
            replaceHexGrid(entries: calculateGrid(for: scale, in: CGRect(origin: .zero, size: CGSize(width: copy.width, height: copy.height))), in: copy)
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
        guard let copy = editorModel.workingCopy, scale > 0, scale != copy.hexMapScale else { return }
        copy.hexMapScale = scale
        editorModel.hexScale = scale
        replaceHexGrid(entries: calculateGrid(for: scale, in: CGRect(origin: .zero, size: CGSize(width: copy.width, height: copy.height))), in: copy)
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
    private func syncDisplayEntries(from copy: MapModel, editorModel: MapEditorSession) {
        let activeEntryId = editorModel.editEntries.entries.first?.id
        let displayEntries = copy.entries.filter { $0.id != activeEntryId }
        editorModel.entries.resetEntries(mapId: copy.id, entries: displayEntries)
    }

    @MainActor private func initHexGridSize(model: MapModel, size: Double) -> Double {
        guard size < 10 else { return size }
        let wScale = model.width / (12 * sqrt(3))
        let hScale = model.height / (12 * (3.0 / 2.0))
        return max(wScale, hScale)
    }

    @MainActor private func replaceHexGrid(entries: [MapEntryModel], in model: MapModel) {
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

// MARK: - Entry Boundary (working copy only)

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
