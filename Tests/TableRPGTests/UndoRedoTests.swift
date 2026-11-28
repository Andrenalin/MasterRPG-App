// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT §5.1: redo must bring back the state that undo removed. The undo stack only held the
/// state from when the item was selected, so redo applied the original and dropped the last edit.
@MainActor
@Suite("Undo and redo through EditControllable")
struct UndoRedoTests {
    @MainActor private struct Fixture {
        let root: TableRootModel
        let id: UUID

        func name(of id: UUID? = nil) -> String? {
            root.itemController.itemSync(for: id ?? self.id)?.name
        }

        func rename(_ name: String, id: UUID? = nil) {
            root.editController.reset(name: name, itemId: id ?? self.id, forceSave: false)
        }

        /// Selects the item the way the editor does, which starts a fresh undo history.
        func select(_ id: UUID? = nil) {
            root.editController.editorModel.undoManaged.removeAll()
        }
    }

    private func fixture(name: String = "Original") async -> Fixture {
        let root = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let id = await root.itemController.addNew(type: .item)
        root.editController.save(
            updated: TableModel(id: id, name: name, description: "", tags: [], category: .loot, displayState: 0, tableType: .list, diceId: nil, entries: [], parentId: nil),
            message: "Create table",
            forceSave: false
        )
        let fixture = Fixture(root: root, id: id)
        fixture.select()
        return fixture
    }

    @Test("Edit, edit, undo, undo, redo, redo walks the history in both directions")
    func redoReplaysEveryUndoneEdit() async {
        let fixture = await fixture()
        fixture.rename("A")
        fixture.rename("B")
        #expect(fixture.name() == "B")

        fixture.root.editController.undo()
        #expect(fixture.name() == "A")
        fixture.root.editController.undo()
        #expect(fixture.name() == "Original")

        fixture.root.editController.redo()
        #expect(fixture.name() == "A")
        fixture.root.editController.redo()
        #expect(fixture.name() == "B", "redo must restore the last edit, not the state from when the item was selected")
    }

    @Test("A single edit can be undone and redone")
    func singleEditRoundTrip() async {
        let fixture = await fixture()
        fixture.rename("Edited")

        fixture.root.editController.undo()
        #expect(fixture.name() == "Original")
        fixture.root.editController.redo()

        #expect(fixture.name() == "Edited", "redo after one edit used to leave the item at its original state")
    }

    @Test("Undoing and redoing interleaved edits of two items restores each item's own state")
    func historyAcrossTwoItems() async {
        let fixture = await fixture(name: "First")
        let secondId = await fixture.root.itemController.addNew(type: .item)
        fixture.root.editController.save(
            updated: TableModel(id: secondId, name: "Second", description: "", tags: [], category: .loot, displayState: 0, tableType: .list, diceId: nil, entries: [], parentId: nil),
            message: "Create table",
            forceSave: false
        )
        fixture.select()

        fixture.rename("First edited")
        fixture.rename("Second edited", id: secondId)

        fixture.root.editController.undo()
        #expect(fixture.name(of: secondId) == "Second")
        #expect(fixture.name() == "First edited")
        fixture.root.editController.undo()
        #expect(fixture.name() == "First")

        fixture.root.editController.redo()
        #expect(fixture.name() == "First edited")
        #expect(fixture.name(of: secondId) == "Second")
        fixture.root.editController.redo()
        #expect(fixture.name(of: secondId) == "Second edited")
        #expect(fixture.name() == "First edited")
    }

    @Test("A new edit after an undo clears redo")
    func newEditClearsRedo() async {
        let fixture = await fixture()
        fixture.rename("A")
        fixture.root.editController.undo()
        #expect(fixture.root.editController.canRedo)

        fixture.rename("B")

        #expect(!fixture.root.editController.canRedo)
        #expect(fixture.name() == "B")
    }
}
#endif
