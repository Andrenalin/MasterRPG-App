// @copyright André Trettin

import CharacterRPG
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI

// Split out of MapEditController.swift — see CODE_AUDIT §9.13.

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
        addEntry(coordinates: [], editorModel: editorModel)
    }

    /// Adds a room with the given outline and makes it the room being edited.
    @MainActor
    private func addEntry(coordinates: [CGPoint], editorModel: MapEditorSession) -> UUID? {
        guard let copy = editorModel.workingCopy else { return nil }
        synchronizeWorkingCopy(editorModel: editorModel)
        var entry = MapEntryModel.empty
        entry.coordinates = coordinates
        copy.entries.append(entry)
        editController.editorModel.sheetEditorModel.entryId = entry.id
        editorModel.editEntries.resetEntries(mapId: copy.id, entries: [entry])
        synchronizeRoomPresentation(from: copy, editorModel: editorModel)
        recordMutation(
            coordinates.isEmpty
                ? String(localized: "Add map area", bundle: .module)
                : String(localized: "Draw map area", bundle: .module),
            editorModel: editorModel
        )
        return entry.id
    }

    /// Makes an Apple Pencil outline the shape of the room being edited, or a new room when no
    /// room is being edited. One undo step either way.
    @MainActor
    @discardableResult
    func applyPencilRoom(_ polygon: [CGPoint], editorModel: MapEditorSession) -> Bool {
        guard polygon.count >= 3, !editorModel.configuration.isTileEditor else { return false }
        if var entry = editorModel.editEntries.entries.first {
            entry.coordinates = polygon
            editorModel.editEntries.setEntry(entry: entry)
            editorModel.workingCopy?[entry.id] = entry
            return recordMutation(
                String(localized: "Draw map area", bundle: .module),
                editorModel: editorModel
            )
        }
        return addEntry(coordinates: polygon, editorModel: editorModel) != nil
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

// MARK: - Character Links

extension MapEditController {
    /// Appends a link of each character to the room's content, unless the room already links
    /// that character. Links of other characters stay. Part of the caller's mutation: it
    /// records no history entry itself, and it changes the editor's working copy only. The
    /// stored map is written when the editor commits, so the editor's undo and the external
    /// merge stay in charge of it. See CODE_AUDIT_23 §5.11.
    @MainActor
    func appendCharacterLinks(
        _ characterIds: [UUID],
        to entryId: UUID?,
        editorModel: MapEditorSession
    ) {
        guard let copy = editorModel.workingCopy,
              let entryId,
              copy.entries.contains(where: { $0.id == entryId }) else { return }
        synchronizeWorkingCopy(editorModel: editorModel)

        var entry = copy[entryId]
        let originalContent = entry.content
        var content = originalContent.trimmingCharacters(in: .whitespaces)
        for characterId in characterIds {
            let isLinked = LinkReplaceController.links(for: content)
                .contains { $0.module == .value && $0.itemId == characterId && $0.entryId == nil }
            guard !isLinked else { continue }
            let link = LinkBuilder.markdown(
                name: editController.root.characterRoot.linkControllable.name(for: characterId),
                module: .value,
                itemId: characterId
            )
            content += content.isEmpty ? link : " " + link
        }
        guard content != originalContent else { return }
        entry.content = content
        copy[entryId] = entry
        synchronizeRoomPresentation(from: copy, editorModel: editorModel)
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
