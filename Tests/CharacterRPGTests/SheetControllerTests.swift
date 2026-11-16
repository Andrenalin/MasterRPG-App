// @copyright André Trettin

#if canImport(Testing)
import Foundation
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import CharacterRPG

@MainActor
struct SheetControllerTests {
    func linkRegisterController(for root: CharacterRootModel) -> LinkRegisterController {
        LinkRegisterController(root: RootManager.init(anyRoot: root))
    }

    @Test func characterSheetEditTypeControllerPersistsSelectedType() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = try #require(root.itemController.itemDataModel.items.first)
        let entryID = try #require(root.itemController.itemOrEmpty(for: itemId).entries.first?.id)

        root.editController.updateSheetEditType(
            itemId: itemId,
            entryId: entryID,
            editType: .selection
        )

        #expect(root.itemController.itemOrEmpty(for: itemId)[entryID].type == .selection)
    }
    
    @Test func characterSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        // Create RootManager for testing
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.name == "Adalbert Unheil")
        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.item)
        #expect(model.source.itemId == itemId)
    }

    @Test func characterSheetWithPhoto() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        // Character sheets with displayState == 0 should have showHeader set
        let item = root.itemController.itemOrEmpty(for: itemId!)
        if item.displayState == 0 {
            #expect(model.showHeader == true)
        } else {
            #expect(model.showHeader == false)
        }
    }

    @Test func characterSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.entries.count > 0)
        // Each entry should have proper source and be at the same level
        for entry in model.entries where entry.sheetType != SheetModelType.photo {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 0)
        }
    }

    @Test func characterSheetWithValueLink() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        // Find entry with valueId (group type)
        let groupEntry = model.entries.first(where: { $0.sheetType == SheetModelType.group })
        if let groupEntry {
            #expect(groupEntry.entries.count > 0)
            #expect(groupEntry.entries.first?.isShown == false) // Value links default to hidden
        }
    }

    @Test func characterSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let modelShown = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: false, isEditor: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func characterSheetWithDice() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        // Find entry with diceId
        let entryWithDice = model.entries.first(where: { !$0.inlineEntries.isEmpty })
        if let entryWithDice {
            let diceInline = entryWithDice.inlineEntries.first(where: { $0.sheetType == SheetModelType.dice })
            #expect(diceInline != nil)
        }
    }

    @Test func characterSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        // Test isFolded at moduleDepth >= 1
        let modelFolded = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        #expect(modelFolded.isFolded == true)
        #expect(modelFolded.entries.isEmpty)

        let modelNotFolded = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: false)
        #expect(modelNotFolded.isFolded == false)

        // Test isFolded in editor mode at level > 0
        let modelFoldedEditor = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 1, isShown: true, moduleDepth: 0, isEditor: true)
        #expect(modelFoldedEditor.isFolded == true)
        #expect(modelFoldedEditor.entries.isEmpty)
    }

    @Test func characterUpdateRefreshesInlineLinksAndEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = UUID()
        let originalDiceId = UUID()
        let updatedDiceId = UUID()
        let originalPhotoId = UUID()
        let updatedPhotoId = UUID()
        let keptEntry = ValueEntryModel(id: UUID(), name: "Old Value", type: .number, value: "5", diceId: originalDiceId)
        let removedEntry = ValueEntryModel(id: UUID(), name: "Removed Value", type: .text, value: "Gone")
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        root.itemController.replace(
            model: ValueModel(
                id: itemId,
                name: "Old Character",
                description: "Old description",
                category: .character,
                photoId: originalPhotoId,
                entries: [keptEntry, removedEntry],
                diceId: originalDiceId
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)

        let updatedEntry = ValueEntryModel(id: keptEntry.id, name: "Updated Value", type: .number, value: "7", diceId: updatedDiceId)
        let newEntry = ValueEntryModel(id: UUID(), name: "New Value", type: .number, value: "0|7")
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.name = "Updated Character"
        item.description = "Updated description"
        item.photoId = updatedPhotoId
        item.diceId = updatedDiceId
        item.entries = [updatedEntry, newEntry]

        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Updated Character")
        #expect(sheetModel.description == "Updated description")
        #expect(sheetModel.inlineEntries.map(\.source.itemId).contains(updatedDiceId))
        #expect(sheetModel.inlineEntries.map(\.source.itemId).contains(updatedPhotoId))
        #expect(sheetModel.entries.map(\.source.entryId).contains(keptEntry.id))
        #expect(!sheetModel.entries.map(\.source.entryId).contains(removedEntry.id))
        #expect(sheetModel.entries.map(\.source.entryId).contains(newEntry.id))
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.name == "Updated Value")
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.description == "7")
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.inlineEntries.map(\.source.itemId) == [updatedDiceId])
    }

    @Test func characterSheetGroupEntryHasNoDiceInline() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = UUID()
        let diceId = UUID()
        let entry = ValueEntryModel(id: UUID(), name: "Skills", type: .number, value: "", diceId: diceId)
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )
        root.itemController.replace(
            model: ValueModel(id: itemId, name: "Character", description: "", category: .character, entries: [entry]),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)
        let plain = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id }))
        #expect(plain.inlineEntries.contains(where: { $0.sheetType == .dice }), "A plain entry keeps its dice")

        _ = await root.editController.convertToGroup(itemId: itemId, entryId: entry.id, existingItemId: nil)
        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)
        let group = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id }))
        #expect(group.sheetType == .group)
        #expect(group.inlineEntries.isEmpty, "A group value shows no dice inline")

        // Built fresh from the stored group, too.
        let rebuilt = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)
        let rebuiltGroup = try #require(rebuilt.entries.first(where: { $0.source.entryId == entry.id }))
        #expect(rebuiltGroup.sheetType == .group)
        #expect(rebuiltGroup.inlineEntries.isEmpty)
    }

    @Test func characterSheetSubValueHasNoItemDiceOrPhotoInline() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let parentId = UUID()
        let subValueId = UUID()
        let entry = ValueEntryModel(id: UUID(), name: "Skills", type: .text, value: "", valueId: subValueId)
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )
        root.itemController.replace(
            model: ValueModel(id: subValueId, name: "Skill list", description: "", category: .character, photoId: UUID(), entries: [], diceId: UUID()),
            isInsert: true
        )
        root.itemController.replace(
            model: ValueModel(id: parentId, name: "Character", description: "", category: .character, entries: [entry]),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: parentId, destination: nil, level: 0, isShown: true, isEditor: false)
        let group = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id }))
        let subValue = try #require(group.entries.first(where: { $0.source.itemId == subValueId }))
        #expect(subValue.inlineEntries.isEmpty, "A group's sub-value shows neither its dice nor its photo")

        // The update path (which refreshes existing models) keeps them hidden too.
        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)
        let updatedSubValue = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id })?.entries.first(where: { $0.source.itemId == subValueId }))
        #expect(updatedSubValue.inlineEntries.isEmpty)

        // A top-level sheet of the same value keeps its dice and photo.
        let standalone = sut.sheet(root: rootManager, itemId: subValueId, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(Set(standalone.inlineEntries.map(\.sheetType)) == [.dice, .photo])
    }

    @Test func characterUpdateRefreshesEntryConvertedToGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = UUID()
        let entry = ValueEntryModel(id: UUID(), name: "Skills", type: .text, value: "A collection of skills.")
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        root.itemController.replace(
            model: ValueModel(id: itemId, name: "Character", description: "", category: .character, entries: [entry]),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)
        let entrySheet = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id }))
        #expect(entrySheet.sheetType == .item)

        let groupId = await root.editController.convertToGroup(itemId: itemId, entryId: entry.id, existingItemId: nil)

        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)

        let updatedEntrySheet = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id }))
        #expect(updatedEntrySheet.sheetType == .group, "Converting an entry to a group must refresh its sheetType")
        #expect(updatedEntrySheet.entries.contains(where: { $0.source.itemId == groupId }), "Converting an entry to a group must surface the new group's nested sheet")
    }

    @Test func convertToGroupResetsCachedLinkHighlightTextModel() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = UUID()
        let entry = ValueEntryModel(id: UUID(), name: "Skills", type: .text, value: "A collection of skills.")
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        root.itemController.replace(
            model: ValueModel(id: itemId, name: "Character", description: "", category: .character, entries: [entry]),
            isInsert: true
        )

        let sheetController = SheetController(itemController: root.itemController, linkController: root.linkController)
        let sheetRootModel = SheetRootModel(rootManager: rootManager, linkControllable: root.linkController, sheetControllable: sheetController, itemId: itemId, isEditor: false)

        // Simulate the row already having been rendered (and its name text cached) before conversion.
        let nameModel = sheetRootModel.linkTextModel(for: .entry(entry.id), text: "Skills")
        #expect(nameModel.text == "Skills")

        let groupId = await sheetRootModel.convertEntryToGroup(
            source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: .value),
            existingItemId: nil
        )
        #expect(groupId != nil)

        // The cached model must pick up the new link text on its own, without requiring the
        // owning view to be torn down and rebuilt.
        #expect(nameModel.text != "Skills", "Cached LinkHighlightTextModel must be reset after converting an entry to a group")
        #expect(nameModel.text.contains("\(URL.appScheme)://"), "Cached LinkHighlightTextModel must reflect the entry's new link text")
    }

    @Test func convertToGroupRefreshesFolderList() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Character", itemId: itemId)
        let entry = ValueEntryModel(id: UUID(), name: "Skills", type: .text, value: "A collection of skills.")
        root.editController.add(entry: entry, itemId: itemId)

        let existingItemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Inventory", itemId: existingItemId)

        await root.folderListController.performSearch(source: "test")
        #expect(root.folderListController.listModel.list.contains(where: { $0.source.itemId == existingItemId }), "Precondition: the reused item starts out visible in the root list")

        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )
        let sheetController = SheetController(itemController: root.itemController, linkController: root.linkController)
        let sheetRootModel = SheetRootModel(rootManager: rootManager, linkControllable: root.linkController, sheetControllable: sheetController, itemId: itemId, isEditor: false)

        _ = await sheetRootModel.convertEntryToGroup(
            source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: .value),
            existingItemId: existingItemId
        )

        // `FolderListControllable.update(debounce:)` refreshes via a detached Task.
        #expect(
            await waitUntil { !root.folderListController.listModel.list.contains(where: { $0.source.itemId == existingItemId }) },
            "Converting an entry to a group must refresh the item list so the now-hidden item disappears"
        )
    }

    @Test func characterUpdateLeavesFoldedEntriesCollapsed() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController, linkController: root.linkController)
        let itemId = UUID()
        let rootManager = RootManager(
            adventureRoot: root,
            audioRoot: root,
            characterRoot: root,
            diceRoot: root.diceRoot,
            generatorRoot: root,
            mapRoot: root,
            pdfRoot: root.pdfRoot,
            photoRoot: root.photoRoot,
            spaceRoot: root,
            tableRoot: root.tableRoot,
            weatherRoot: root
        )

        root.itemController.replace(
            model: ValueModel(
                id: itemId,
                name: "Folded Character",
                description: "Folded description",
                category: .character,
                entries: [ValueEntryModel(id: UUID(), name: "Hidden", type: .text, value: "Hidden text")]
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        root.itemController.itemOrEmpty(for: itemId).name = "Folded Updated"

        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Folded Updated")
        #expect(sheetModel.isFolded)
        #expect(sheetModel.entries.isEmpty)
    }
}
#endif
