// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §8.5: what the group editor shows for several selected items. What it saves
/// back is tested with a real module root in `GroupEditorSaveTests` (the fake item model never
/// applies a change).
@MainActor
@Suite("Group editor controller")
struct GroupEditorControllerTests {
    private struct Fixture {
        let itemController: FakeItemController
        let editController: FakeEditController
        let ids: [UUID]
    }

    private static func fixture(_ items: [(name: String, description: String, tags: [String])]) -> Fixture {
        let itemController = FakeItemController(
            config: FakeModuleConfiguration(),
            linkRegisterController: LinkRegisterController(root: nil),
            itemDataModel: ItemDataModel()
        )
        let editController = FakeEditController(
            itemControllable: itemController,
            tagController: TagController(),
            linkRegisterController: LinkRegisterController(root: nil),
            editorModel: ItemEditorModel(sheetEditorModel: SheetEditorModel()),
            cacheItemListModel: CacheItemListModel()
        )
        var ids: [UUID] = []
        for item in items {
            let model = FakeItemModel(name: item.name, description: item.description, tags: item.tags)
            itemController.itemDataModel.setItem(id: model.id, item: model)
            itemController.itemDataModel.insert(itemId: model.id, at: nil)
            ids.append(model.id)
        }
        return Fixture(itemController: itemController, editController: editController, ids: ids)
    }

    private static func controller(_ fixture: Fixture) -> GroupEditorController {
        GroupEditorController(itemController: fixture.itemController, editController: fixture.editController, ids: fixture.ids)
    }

    // MARK: - What the editor starts with

    @Test("Items that agree show their shared name, description and tags")
    func agreeingItemsShowTheirValues() {
        let fixture = Self.fixture([("Goblin", "Small", ["monster", "forest"]), ("Goblin", "Small", ["monster", "forest"])])

        let model = Self.controller(fixture).model

        #expect(model.namePlaceHolder == "Goblin")
        #expect(model.descriptionPlaceHolder == "Small")
        #expect(model.tags == ["monster", "forest"])
        #expect(model.tagsPlaceHolder == "monster forest")
        #expect(model.name.isEmpty, "the name field starts empty; the shared name is only the placeholder")
    }

    @Test("Items that differ show the different-values placeholders and start without tags")
    func differingItemsShowPlaceholders() {
        let fixture = Self.fixture([("Goblin", "Small", ["monster"]), ("Orc", "Large", ["monster", "cave"])])

        let model = Self.controller(fixture).model

        #expect(model.namePlaceHolder != "Goblin" && model.namePlaceHolder != "Orc")
        #expect(model.descriptionPlaceHolder != "Small" && model.descriptionPlaceHolder != "Large")
        #expect(model.tags.isEmpty, "a mix of tags is no starting set")
        #expect(model.originalTags.isEmpty)
    }

    @Test("Name, description and tags are compared separately")
    func fieldsAreComparedSeparately() {
        let fixture = Self.fixture([("Same", "One", ["a"]), ("Same", "Two", ["a"])])

        let model = Self.controller(fixture).model

        #expect(model.namePlaceHolder == "Same")
        #expect(model.descriptionPlaceHolder != "One")
        #expect(model.tags == ["a"])
    }

    @Test("Three items where only the last one differs are different")
    func lateDifferenceIsFound() {
        let fixture = Self.fixture([("A", "", []), ("A", "", []), ("B", "", [])])

        let model = Self.controller(fixture).model

        #expect(model.namePlaceHolder != "A")
    }

    @Test("An unknown id is skipped")
    func unknownIdIsSkipped() {
        let fixture = Self.fixture([("Goblin", "", ["x"])])

        let controller = GroupEditorController(
            itemController: fixture.itemController,
            editController: fixture.editController,
            ids: fixture.ids + [UUID()]
        )

        #expect(controller.model.namePlaceHolder == "Goblin")
    }
}
#endif
