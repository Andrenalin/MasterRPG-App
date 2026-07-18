// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import MapRPG

@MainActor
@Suite("Map editor pin history")
struct MapEditorPinHistoryTests {
    @Test("One committed pin mutation can be undone and redone")
    func undoAndRedoPinMutation() throws {
        let original = MapPinModel(id: UUID(), name: "Original")
        var moved = original
        moved.location = CGPoint(x: 120, y: 80)
        let history = MapEditorPinHistory(pins: [original])

        #expect(history.record([moved]))
        #expect(history.canUndo)
        #expect(history.undo() == [original])
        #expect(history.canRedo)
        #expect(history.redo() == [moved])
    }

    @Test("Repeated equivalent commits do not create undo entries")
    func duplicateCommitIsIgnored() {
        let pin = MapPinModel(id: UUID(), name: "Stable")
        let history = MapEditorPinHistory(pins: [pin])

        #expect(!history.record([pin]))
        #expect(!history.canUndo)
    }

    @Test("A new mutation clears redo history")
    func mutationClearsRedo() {
        let original = MapPinModel(id: UUID(), name: "Original")
        var moved = original
        moved.location.x = 10
        var resized = original
        resized.size = .large
        let history = MapEditorPinHistory(pins: [original])

        history.record([moved])
        _ = history.undo()
        #expect(history.canRedo)

        history.record([resized])
        #expect(!history.canRedo)
    }
}
#endif
