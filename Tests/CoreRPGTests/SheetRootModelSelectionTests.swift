// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
struct SheetRootModelSelectionTests {
    func makeRootModel(entryCount: Int = 2, isEditor: Bool = true) -> (rootModel: SheetRootModel, entries: [SheetModel]) {
        let itemId = UUID()
        let source = ItemRowModel(itemId: itemId, typeId: .adventure)
        let entries = (0..<entryCount).map { index in
            SheetModel(source: ItemRowModel(itemId: itemId, entryId: UUID(), typeId: .adventure), level: 1, name: "Entry \(index)", description: "", entries: [])
        }
        let sheetModel = SheetModel(source: source, level: 0, name: "Root", description: "", entries: entries)
        let rootModel = SheetRootModel(
            rootManager: ItemRootController.fake.rootManager!,
            linkControllable: FakeLinkController.fake,
            sheetControllable: FakeSheetController.fake,
            sheetModel: sheetModel,
            isEditor: isEditor
        )
        return (rootModel, entries)
    }

    @Test func setSelectedIsExclusive() async throws {
        let (rootModel, entries) = makeRootModel()

        rootModel.setSelected(entries[0], parent: rootModel.sheetModel)
        #expect(entries[0].isSelected)
        #expect(rootModel.selectedEntryId == entries[0].id)

        rootModel.setSelected(entries[1], parent: rootModel.sheetModel)
        #expect(!entries[0].isSelected)
        #expect(entries[1].isSelected)
        #expect(rootModel.selectedEntryId == entries[1].id)
    }

    @Test func itemDescriptionLinkTogglesExistingChildSheet() {
        let rootItemID = UUID()
        let linkedItemID = UUID()
        let linkedSheet = SheetModel(
            source: ItemRowModel(itemId: linkedItemID, typeId: .adventure),
            level: 1,
            isShown: false,
            name: "Linked",
            description: "",
            entries: []
        )
        let rootSheet = SheetModel(
            source: ItemRowModel(itemId: rootItemID, typeId: .adventure),
            name: "Root",
            description: "",
            entries: [linkedSheet]
        )
        let rootModel = SheetRootModel(
            rootManager: ItemRootController.fake.rootManager!,
            linkControllable: FakeLinkController.fake,
            sheetControllable: FakeSheetController.fake,
            sheetModel: rootSheet,
            isEditor: false
        )

        rootModel.toggle(
            id: .itemContent(rootItemID),
            itemId: linkedItemID,
            module: .adventure,
            linkNumber: 0
        )

        #expect(linkedSheet.isShown)
    }

    /// The header name and the description row cache their own `LinkHighlightTextModel`
    /// (`.item` / `.itemContent`), which ignores the `text` argument once cached — so a
    /// reconcile has to reset both, or a renamed description keeps showing the old text.
    @Test func reconcileRefreshesCachedItemNameAndDescriptionText() {
        let (rootModel, _) = makeRootModel()
        let sheetModel = rootModel.sheetModel
        let itemId = sheetModel.source.itemId
        let nameModel = rootModel.linkTextModel(for: .item(itemId), text: sheetModel.name)
        let descriptionModel = rootModel.linkTextModel(for: .itemContent(itemId), text: "Old description")

        sheetModel.name = "Renamed"
        sheetModel.description = "New description"
        sheetModel.hasChanged = true
        rootModel.performReconcile()

        #expect(nameModel.text == "Renamed")
        #expect(descriptionModel.text == "New description")
        #expect(!sheetModel.hasChanged)
    }

    @Test func duplicateDomainIdentifiersReceiveDistinctModelIDsAndSelectIndependently() async throws {
        let sharedItemID = UUID()
        let sharedEntryID = UUID()
        let firstEntry = SheetModel(
            source: ItemRowModel(itemId: sharedItemID, entryId: sharedEntryID, typeId: .value),
            level: 2,
            name: "First copy",
            description: "",
            entries: []
        )
        let secondEntry = SheetModel(
            source: ItemRowModel(itemId: sharedItemID, entryId: sharedEntryID, typeId: .value),
            level: 2,
            name: "Second copy",
            description: "",
            entries: []
        )
        let sharedSource = ItemRowModel(itemId: sharedItemID, typeId: .value)
        let firstParent = SheetModel(source: sharedSource, level: 1, name: "First parent", description: "", entries: [firstEntry])
        let secondParent = SheetModel(source: sharedSource, level: 1, name: "Second parent", description: "", entries: [secondEntry])
        let rootItemID = UUID()
        let firstContainer = SheetModel(
            source: ItemRowModel(itemId: rootItemID, entryId: UUID(), typeId: .adventure),
            level: 0,
            name: "First container",
            description: "",
            entries: [firstParent]
        )
        let secondContainer = SheetModel(
            source: ItemRowModel(itemId: rootItemID, entryId: UUID(), typeId: .adventure),
            level: 0,
            name: "Second container",
            description: "",
            entries: [secondParent]
        )
        let rootSheet = SheetModel(
            source: ItemRowModel(itemId: rootItemID, typeId: .adventure),
            level: 0,
            name: "Root",
            description: "",
            entries: [firstContainer, secondContainer]
        )
        let rootModel = SheetRootModel(
            rootManager: ItemRootController.fake.rootManager!,
            linkControllable: FakeLinkController.fake,
            sheetControllable: FakeSheetController.fake,
            sheetModel: rootSheet,
            isEditor: true
        )

        #expect(firstEntry.id != secondEntry.id)

        rootModel.setSelected(firstEntry, parent: firstParent)
        rootModel.setSelected(secondEntry, parent: secondParent)

        #expect(!firstEntry.isSelected)
        #expect(secondEntry.isSelected)
        #expect(rootModel.selectedEntry === secondEntry)
        #expect(rootModel.selectedSheetEntryFocusValue?.entryModel === secondEntry)
        #expect(rootModel.selectedSheetEntryFocusValue?.parentModel === secondParent)
    }

    @Test func modelIDAndHashRemainStableWhenMutableSourceFieldsChange() {
        let model = SheetModel(
            source: ItemRowModel(itemId: UUID(), typeId: .photo),
            level: 1,
            type: .photo,
            name: "Image",
            description: "",
            entries: []
        )
        let originalID = model.id
        let models: Set<SheetModel> = [model]

        model.source = ItemRowModel(itemId: UUID(), typeId: .audio)
        model.destination = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
        model.level = 4
        model.sheetType = .audio

        #expect(model.id == originalID)
        #expect(models.contains(model))
    }

    @Test func selectedSheetEntryFocusValueCarriesParentAndEntry() async throws {
        let (rootModel, entries) = makeRootModel()
        #expect(rootModel.selectedSheetEntryFocusValue == nil)

        rootModel.setSelected(entries[0], parent: rootModel.sheetModel)
        let focusValue = rootModel.selectedSheetEntryFocusValue
        #expect(focusValue?.entryModel === entries[0])
        #expect(focusValue?.parentModel === rootModel.sheetModel)
        #expect(focusValue?.isEditor == true)
    }

    @Test func selectedSheetEntryFocusValueIsNilOutsideEditorMode() async throws {
        let (rootModel, entries) = makeRootModel(isEditor: false)
        rootModel.setSelected(entries[0], parent: rootModel.sheetModel)
        #expect(rootModel.selectedSheetEntryFocusValue == nil)
    }

    @Test func clearSelectionDeselectsCurrentEntry() async throws {
        let (rootModel, entries) = makeRootModel()
        rootModel.setSelected(entries[0], parent: rootModel.sheetModel)

        rootModel.clearSelection()
        #expect(!entries[0].isSelected)
        #expect(rootModel.selectedEntryId == nil)
    }

    @Test func resetItemIdClearsSelection() async throws {
        let (rootModel, entries) = makeRootModel()
        rootModel.setSelected(entries[0], parent: rootModel.sheetModel)

        rootModel.reset(itemId: UUID())
        #expect(rootModel.selectedEntryId == nil)
    }

    @Test func setSelectedOnRootRowSkipsScrollWithoutCrashing() async throws {
        let (rootModel, _) = makeRootModel()

        // The root sheetModel's source has no entryId — selecting it as its own parent
        // (the SheetView.nameRow convention) must not crash or set a stray scrollEntryId.
        rootModel.setSelected(rootModel.sheetModel, parent: rootModel.sheetModel)
        #expect(rootModel.sheetModel.isSelected)
        #expect(rootModel.selectedEntryId == rootModel.sheetModel.id)
    }

    @Test func inlineEditingOpensCurrentEntryAndClosesPreviousEntry() {
        // Given
        let (rootModel, entries) = makeRootModel(isEditor: false)

        // When
        rootModel.toggleInlineEditing(entries[0], parent: rootModel.sheetModel)

        // Then
        #expect(rootModel.inlineEditingEntryId == entries[0].id)
        #expect(entries[0].isEditing)

        // When
        rootModel.toggleInlineEditing(entries[1], parent: rootModel.sheetModel)

        // Then
        #expect(rootModel.inlineEditingEntryId == entries[1].id)
        #expect(!entries[0].isEditing)
        #expect(entries[1].isEditing)
    }

    @Test func tappingExpandedInlineEditorClosesIt() {
        // Given
        let (rootModel, entries) = makeRootModel(entryCount: 1, isEditor: false)
        rootModel.toggleInlineEditing(entries[0], parent: rootModel.sheetModel)

        // When
        rootModel.toggleInlineEditing(entries[0], parent: rootModel.sheetModel)

        // Then
        #expect(rootModel.inlineEditingEntryId == nil)
        #expect(!entries[0].isEditing)
    }

}
