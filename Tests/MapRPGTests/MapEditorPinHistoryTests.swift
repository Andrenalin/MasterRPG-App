// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import MapRPG

@MainActor
@Suite("Map editor history")
struct MapEditorHistoryTests {
    @Test("One committed map mutation can be undone and redone")
    func undoAndRedoMutation() throws {
        // Given
        let originalPin = MapPinModel(id: UUID(), name: "Original")
        let original = MapModel(id: UUID(), name: "Map", mapPins: [originalPin])
        let history = MapEditorHistory(map: original)
        let changed = original.copy()
        changed.mapPins[0].location = CGPoint(x: 120, y: 80)

        // When
        let recorded = history.record(
            MapEditorSnapshot(map: changed, activeEntryId: nil),
            title: "Move pin"
        )
        let undone = try #require(history.undo())
        let redone = try #require(history.redo())

        // Then
        #expect(recorded)
        #expect(undone.map.mapPins == [originalPin])
        #expect(redone.map.mapPins == changed.mapPins)
    }

    @Test("Repeated equivalent commits do not create undo entries")
    func duplicateCommitIsIgnored() {
        // Given
        let map = MapModel(id: UUID(), name: "Stable")
        let history = MapEditorHistory(map: map)

        // When
        let recorded = history.record(
            MapEditorSnapshot(map: map.copy(), activeEntryId: nil),
            title: "No change"
        )

        // Then
        #expect(!recorded)
        #expect(!history.canUndo)
    }

    @Test("A new mutation clears redo history")
    func mutationClearsRedo() {
        // Given
        let original = MapModel(id: UUID(), name: "Map")
        let moved = original.copy()
        moved.pinScale = 2
        let resized = original.copy()
        resized.pinScale = 3
        let history = MapEditorHistory(map: original)
        history.record(
            MapEditorSnapshot(map: moved, activeEntryId: nil),
            title: "First"
        )
        _ = history.undo()

        // When
        history.record(
            MapEditorSnapshot(map: resized, activeEntryId: nil),
            title: "Second"
        )

        // Then
        #expect(!history.canRedo)
    }

    @Test("Snapshots restore the active map area")
    func restoresActiveEntry() throws {
        // Given
        let first = MapEntryModel(
            id: UUID(),
            name: "First",
            content: "",
            coordinates: []
        )
        let second = MapEntryModel(
            id: UUID(),
            name: "Second",
            content: "",
            coordinates: []
        )
        let map = MapModel(id: UUID(), name: "Map", entries: [first, second])
        let history = MapEditorHistory(map: map, activeEntryId: first.id)
        history.record(
            MapEditorSnapshot(map: map, activeEntryId: second.id),
            title: "Select and edit"
        )

        // When
        let undone = try #require(history.undo())
        let redone = try #require(history.redo())

        // Then
        #expect(undone.activeEntryId == first.id)
        #expect(redone.activeEntryId == second.id)
    }
}
#endif
