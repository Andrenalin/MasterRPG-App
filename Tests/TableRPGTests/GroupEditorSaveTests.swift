// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT_TestGaps §8.5: what the group editor saves back to the selected items, on a real
/// module root. Saving must never wipe tags the user did not touch (CODE_AUDIT_EditItem §5.6).
@MainActor
@Suite("Group editor save")
struct GroupEditorSaveTests {
    @MainActor private struct Fixture {
        let root: TableRootModel
        let ids: [UUID]

        var controller: GroupEditorController {
            GroupEditorController(itemController: root.itemController, editController: root.editController, ids: ids)
        }

        func table(_ index: Int) -> TableModel? {
            root.itemController.itemSync(for: ids[index])
        }
    }

    private func fixture(_ tables: [(name: String, description: String, tags: [String])]) async -> Fixture {
        let root = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        var ids: [UUID] = []
        for table in tables {
            let id = await root.itemController.addNew(type: .item)
            root.editController.save(
                updated: TableModel(id: id, name: table.name, description: table.description, tags: table.tags, category: .loot, displayState: 0, tableType: .list, diceId: nil, entries: [], parentId: nil),
                message: "Create table"
            )
            ids.append(id)
        }
        return Fixture(root: root, ids: ids)
    }

    @Test("Saving with nothing typed changes nothing")
    func untouchedEditorSavesNothing() async {
        let fixture = await fixture([("Goblin", "Small", ["monster"]), ("Orc", "Large", ["cave"])])

        fixture.controller.save()

        #expect(fixture.table(0)?.name == "Goblin")
        #expect(fixture.table(0)?.tags == ["monster"])
        #expect(fixture.table(1)?.name == "Orc")
        #expect(fixture.table(1)?.tags == ["cave"])
    }

    @Test("Typing a name renames every selected item and leaves their tags and descriptions alone")
    func nameIsAppliedToAll() async {
        let fixture = await fixture([("Goblin", "Small", ["monster"]), ("Orc", "Large", ["cave"])])
        let controller = fixture.controller
        controller.model.name = "Creature"

        controller.save()

        #expect(fixture.table(0)?.name == "Creature")
        #expect(fixture.table(1)?.name == "Creature")
        #expect(fixture.table(0)?.tags == ["monster"])
        #expect(fixture.table(1)?.tags == ["cave"])
        #expect(fixture.table(0)?.description == "Small")
        #expect(fixture.table(1)?.description == "Large")
    }

    @Test("Typing a description applies to every selected item")
    func descriptionIsAppliedToAll() async {
        let fixture = await fixture([("A", "one", []), ("B", "two", [])])
        let controller = fixture.controller
        controller.model.description = "Shared text"

        controller.save()

        #expect(fixture.table(0)?.description == "Shared text")
        #expect(fixture.table(1)?.description == "Shared text")
        #expect(fixture.table(0)?.name == "A")
    }

    @Test("Typing the placeholder name is no change")
    func placeholderNameIsNotAChange() async {
        let fixture = await fixture([("Goblin", "Small", []), ("Goblin", "Small", [])])
        let controller = fixture.controller
        controller.model.name = "Goblin"

        controller.save()

        #expect(fixture.table(0)?.name == "Goblin")
    }

    @Test("Adding a tag to items that share their tags replaces the tags of every item")
    func sharedTagsAreExtended() async {
        let fixture = await fixture([("A", "", ["old"]), ("B", "", ["old"])])
        let controller = fixture.controller
        #expect(controller.model.tags == ["old"])

        controller.model.tags = ["old", "new"]
        controller.save()

        #expect(fixture.table(0)?.tags.sorted() == ["new", "old"])
        #expect(fixture.table(1)?.tags.sorted() == ["new", "old"])
    }

    @Test("Adding a tag to items with different tags adds it to each and keeps their own tags (CODE_AUDIT §5.2)")
    func addedTagIsUnionedIntoDifferingItems() async {
        let fixture = await fixture([("A", "", ["Boss", "Undead"]), ("B", "", ["Elf"]), ("C", "", ["Boss"]), ("D", "", [])])
        let controller = fixture.controller
        #expect(controller.model.tagsAreMixed)
        #expect(controller.model.tags.isEmpty)

        controller.model.tags = ["Act2"]
        controller.save()

        #expect(fixture.table(0)?.tags.sorted() == ["Act2", "Boss", "Undead"])
        #expect(fixture.table(1)?.tags.sorted() == ["Act2", "Elf"])
        #expect(fixture.table(2)?.tags.sorted() == ["Act2", "Boss"])
        #expect(fixture.table(3)?.tags == ["Act2"])
    }

    @Test("A tag an item already has is not added twice, and the shared-tags case is unchanged")
    func unionDoesNotDuplicateAndSharedCaseStaysReplace() async {
        let mixed = await fixture([("A", "", ["Boss"]), ("B", "", ["Elf"])])
        let mixedController = mixed.controller
        mixedController.model.tags = ["Boss", "Act2"]
        mixedController.save()

        #expect(mixed.table(0)?.tags.sorted() == ["Act2", "Boss"])
        #expect(mixed.table(1)?.tags.sorted() == ["Act2", "Boss", "Elf"])

        let shared = await fixture([("A", "", ["old", "gone"]), ("B", "", ["old", "gone"])])
        let sharedController = shared.controller
        #expect(!sharedController.model.tagsAreMixed)
        sharedController.model.tags = ["old"]
        sharedController.save()

        #expect(shared.table(0)?.tags == ["old"], "items that agree can still remove a shared tag")
        #expect(shared.table(1)?.tags == ["old"])
    }

    @Test("An untouched tag editor never clears the tags of items that differ")
    func differingTagsAreKept() async {
        let fixture = await fixture([("A", "", ["x"]), ("B", "", ["y"])])
        let controller = fixture.controller
        #expect(controller.model.tags.isEmpty)
        controller.model.name = "Renamed"

        controller.save()

        #expect(fixture.table(0)?.tags == ["x"])
        #expect(fixture.table(1)?.tags == ["y"])
    }
}
#endif
