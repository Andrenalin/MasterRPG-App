// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §5.15: the module picker state of the link editor: which row a module
/// belongs to, and which selection model a module uses.
@MainActor
@Suite("Editor link model")
struct EditorLinkModelTests {
    private func model(first: [NetworkModules] = [.photo, .map, .table], second: [NetworkModules] = [.audio, .pdf], selection: NetworkModules = .photo) -> EditorLinkModel {
        EditorLinkModel(folderListController: FakeFolderListController(), firstRow: first, secondRow: second, selection: selection)
    }

    @Test("The initial selection is marked in the row it belongs to")
    func initialSelectionRow() {
        let inFirst = model(selection: .map)
        #expect(inFirst.selection == .map)
        #expect(inFirst.selectionFirstRow == .map)
        #expect(inFirst.selectionSecondRow == nil)

        let inSecond = model(selection: .pdf)
        #expect(inSecond.selectionFirstRow == nil)
        #expect(inSecond.selectionSecondRow == .pdf)
    }

    @Test("Changing the selection moves the marker between the two rows")
    func selectionMovesBetweenRows() {
        let model = model(selection: .photo)

        model.update(selection: .audio)
        #expect(model.selection == .audio)
        #expect(model.selectionFirstRow == nil)
        #expect(model.selectionSecondRow == .audio)

        model.update(selection: .table)
        #expect(model.selectionFirstRow == .table)
        #expect(model.selectionSecondRow == nil)
    }

    @Test("A module in neither row leaves the markers as they were")
    func moduleInNoRow() {
        let model = model(selection: .photo)

        model.update(selection: .dice)

        #expect(model.selection == .dice)
        #expect(model.selectionFirstRow == .photo)
        #expect(model.selectionSecondRow == nil)
    }

    @Test("The module row is the first row followed by the second")
    func modulesRow() {
        #expect(model().modulesRow == [.photo, .map, .table, .audio, .pdf])
        #expect(model(second: []).modulesRow == [.photo, .map, .table])
    }

    @Test("Every module has its own selection model, and the modules without one use the adventure's")
    func selectionModelPerModule() {
        let model = model()

        let own: [NetworkModules] = [.audio, .dice, .map, .pdf, .photo, .rule, .space, .table, .value, .weather]
        let models = own.map { ObjectIdentifier(model.selectionModel(for: $0)) }
        #expect(Set(models).count == own.count, "each module has its own")
        #expect(model.selectionModel(for: .adventure) === model.adventureSelectionModel)
        for module in [NetworkModules.none, .game, .setting, .editor, .search, .generator] {
            #expect(model.selectionModel(for: module) === model.adventureSelectionModel)
        }
        #expect(model.selectionModel(for: .value) === model.characterSelectionModel)
    }

    @Test("Only pdf and rule selections allow picking an entry by default")
    func entrySelectionDefaults() {
        let model = model()

        #expect(model.pdfSelectionModel.allowEntrySelection)
        #expect(model.ruleSelectionModel.allowEntrySelection)
        #expect(!model.photoSelectionModel.allowEntrySelection)
        #expect(!model.tableSelectionModel.allowEntrySelection)
    }

    @Test("Without a root manager the list state is left alone and no link is added")
    func withoutRootManager() {
        let model = model()
        model.folderListController.searchModel.searchText = "keep"

        model.update()
        model.updateListController()

        #expect(model.folderListController.searchModel.searchText == "keep")
    }
}
