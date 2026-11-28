// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT_28 §5.3: undo and redo restore a stored value through `replace`, which skipped what
/// `saveChanges` does: the link register and the tag counts.
@MainActor
@Suite("Undo and redo keep the link register and tag counts")
struct UndoSideEffectsTests {
    private func fixture() async -> (root: TableRootModel, id: UUID) {
        let root = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let id = await root.itemController.addNew(type: .item)
        root.editController.save(
            updated: TableModel(id: id, name: "Table", description: "", tags: [], category: .loot, displayState: 0, tableType: .list, diceId: nil, entries: [], parentId: nil),
            message: "Create table",
            forceSave: false
        )
        root.editController.editorModel.undoManaged.removeAll()
        return (root, id)
    }

    private func links(_ root: TableRootModel, of id: UUID) -> Int {
        root.editController.linkRegisterController.model.sourceItems[id]?.count ?? 0
    }

    private func tagCount(_ root: TableRootModel, _ tag: String) -> Int {
        root.editController.tagController.model.tags[.table]?[tag]?.count ?? 0
    }

    @Test("Undoing an added link removes it from the register, redo adds it again")
    func undoLinkUpdatesRegister() async throws {
        let (root, id) = await fixture()
        let target = UUID()
        let content = LinkBuilder.markdown(name: "Book", module: .pdf, itemId: target)
        let model = try #require(root.editController.editModel(for: id))
        model.entries = [TableEntryModel(id: UUID(), name: "Row", content: content)]
        root.editController.save(updated: model, message: "Add link", forceSave: false)
        try #require(links(root, of: id) == 1)

        root.editController.undo()
        #expect(links(root, of: id) == 0, "the delete-impact panel would still list the removed link")

        root.editController.redo()
        #expect(links(root, of: id) == 1)
    }

    @Test("Undoing a tag edit and a trash step keeps the tag counts")
    func undoTagsAndTrashUpdateCounts() async throws {
        let (root, id) = await fixture()
        root.editController.reset(tags: ["hero"], itemId: id, forceSave: false)
        try #require(tagCount(root, "hero") == 1)

        root.editController.undo()
        #expect(tagCount(root, "hero") == 0)
        root.editController.redo()
        #expect(tagCount(root, "hero") == 1)

        root.editController.markForDeletion(itemId: id, forceSave: false)
        try #require(tagCount(root, "hero") == 0)
        root.editController.undo()
        #expect(root.itemController.itemSync(for: id)?.isHidden == false)
        #expect(tagCount(root, "hero") == 1, "a restored item's tags dropped out of the suggestions")
    }
}
#endif
