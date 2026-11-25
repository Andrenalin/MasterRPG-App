// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Folder list keyboard selection")
struct FolderListKeyboardSelectionTests {
    @Test("Down and up move the focus to the next and previous row")
    func movesFocusBetweenRows() {
        let rows = (0..<3).map { _ in makeRow() }
        let model = makeModel(rows)

        #expect(model.rowId(offsetBy: 1, from: rows[0].id) == rows[1].id)
        #expect(model.rowId(offsetBy: 1, from: rows[1].id) == rows[2].id)
        #expect(model.rowId(offsetBy: -1, from: rows[2].id) == rows[1].id)
    }

    @Test("The focus stops at the first and last row")
    func stopsAtTheEnds() {
        let rows = (0..<3).map { _ in makeRow() }
        let model = makeModel(rows)

        #expect(model.rowId(offsetBy: 1, from: rows[2].id) == rows[2].id)
        #expect(model.rowId(offsetBy: -1, from: rows[0].id) == rows[0].id)
    }

    @Test("Without a focused row, down starts at the first row and up at the last row")
    func startsAtAnEndWithoutFocus() {
        let rows = (0..<3).map { _ in makeRow() }
        let model = makeModel(rows)

        #expect(model.rowId(offsetBy: 1, from: nil) == rows[0].id)
        #expect(model.rowId(offsetBy: -1, from: nil) == rows[2].id)
        #expect(model.rowId(offsetBy: 1, from: UUID()) == rows[0].id)
    }

    @Test("An empty list has no row to focus")
    func emptyList() {
        #expect(makeModel([]).rowId(offsetBy: 1, from: nil) == nil)
    }

    @Test("Toggling a row selects it and deselects it again")
    func togglesSelection() {
        let rows = (0..<2).map { _ in makeRow() }
        let model = makeModel(rows, selectionMode: true)

        model.toggleListSelection(of: rows[0].id)
        model.toggleListSelection(of: rows[1].id)
        #expect(model.listSelection == [rows[0].id, rows[1].id])

        model.toggleListSelection(of: rows[0].id)
        #expect(model.listSelection == [rows[1].id])
    }
}

private extension FolderListKeyboardSelectionTests {
    func makeModel(_ rows: [FolderListItemModel], selectionMode: Bool = false) -> FolderListModel {
        let model = FolderListModel(isSelectionMode: selectionMode, navigationModel: ModuleNavigationModel())
        model.list = rows
        return model
    }

    func makeRow() -> FolderListItemModel {
        let id = UUID()
        return FolderListItemModel(
            id: id,
            source: ItemRowModel(itemId: id, typeId: .none),
            level: 0,
            isShown: false
        )
    }
}
