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
}
