// @copyright André Trettin

#if canImport(Testing)
import DiceRPG
import Foundation
import PdfRPG
import PhotoRPG
import TableRPG
import Testing

@testable import CoreRPG
@testable import CharacterRPG

/// The "Add Links" context menu of a sheet row opens the link picker (`EditorLinkView`) as a
/// modal. The picker writes the links straight through the edit controller, so the sheet that
/// opened it has to be reconciled explicitly — it used to stay stale until the sheet models
/// were rebuilt by selecting another item and coming back.
@MainActor
struct SheetLinkSelectionTests {
    private static func makeRoot() -> CharacterRootModel {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        return CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }

    private static func makeSheet(root: CharacterRootModel, itemId: UUID) throws -> SheetRootModel {
        SheetRootModel(
            rootManager: try #require(root.rootManager),
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: true
        )
    }

    /// Mirrors the picker's Done button: add the selected links, then tell the opener.
    private static func commitPicker(root: CharacterRootModel, itemId: UUID, entryId: UUID) {
        root.editorLinkModel.addLinkAndReset(editController: root.editController, destinationItemId: itemId, destinationEntryId: entryId)
        root.editController.editorModel.finishLinkSelection(itemId: itemId, entryId: entryId)
    }

    @Test func pickedLinkShowsUpInTheSheetThatOpenedThePicker() throws {
        let root = Self.makeRoot()
        let itemId = UUID()
        let entry = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "0|7")
        let diceId = UUID()
        root.itemController.replace(model: ValueModel(id: itemId, name: "Hero", description: "", category: .character, entries: [entry]), isInsert: true)

        let sheet = try Self.makeSheet(root: root, itemId: itemId)
        let entryModel = try #require(sheet.sheetModel.entries.first { $0.source.entryId == entry.id })
        #expect(entryModel.inlineEntries.isEmpty)

        // SheetContextMenuLinkButton: register the opener, then present the picker.
        root.editController.editorModel.beginLinkSelection(for: entryModel.source, in: sheet)
        root.editorLinkModel.diceSelectionModel.toggleSelection(itemId: diceId, entryId: nil, isCollection: false)
        Self.commitPicker(root: root, itemId: itemId, entryId: entry.id)

        #expect(root.itemController.itemOrEmpty(for: itemId)[entry.id].diceId == diceId)
        #expect(entryModel.inlineEntries.map(\.source.itemId) == [diceId])
    }

    @Test func pickerForAnotherEntryKeepsTheRegistration() throws {
        let root = Self.makeRoot()
        let itemId = UUID()
        let entry = ValueEntryModel(id: UUID(), name: "Strength", type: .number, value: "0|7")
        let otherEntry = ValueEntryModel(id: UUID(), name: "Agility", type: .number, value: "0|5")
        let diceId = UUID()
        root.itemController.replace(model: ValueModel(id: itemId, name: "Hero", description: "", category: .character, entries: [entry, otherEntry]), isInsert: true)

        let sheet = try Self.makeSheet(root: root, itemId: itemId)
        let entryModel = try #require(sheet.sheetModel.entries.first { $0.source.entryId == entry.id })
        root.editController.editorModel.beginLinkSelection(for: entryModel.source, in: sheet)

        // A picker opened elsewhere (the entry editor's own Add Link button) for another entry.
        root.editorLinkModel.diceSelectionModel.toggleSelection(itemId: UUID(), entryId: nil, isCollection: false)
        Self.commitPicker(root: root, itemId: itemId, entryId: otherEntry.id)
        #expect(entryModel.inlineEntries.isEmpty)

        root.editorLinkModel.diceSelectionModel.toggleSelection(itemId: diceId, entryId: nil, isCollection: false)
        Self.commitPicker(root: root, itemId: itemId, entryId: entry.id)
        #expect(entryModel.inlineEntries.map(\.source.itemId) == [diceId])
    }
}
#endif
