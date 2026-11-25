// @copyright André Trettin

import CoreGraphics
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

@MainActor
@Suite("Folder list range selection")
struct FolderListRangeSelectionTests {
    @Test("A range from an unselected row selects every row it covers")
    func rangeSelectsRows() {
        let rows = makeRows(5)
        let model = makeModel(rows)

        model.beginRangeSelection(at: rows[1].id)
        model.extendRangeSelection(to: rows[3].id)

        #expect(model.listSelection == [rows[1].id, rows[2].id, rows[3].id])
    }

    @Test("A range from a selected row deselects every row it covers")
    func rangeDeselectsRows() {
        let rows = makeRows(5)
        let model = makeModel(rows)
        model.listSelection = Set(rows.map(\.id))

        model.beginRangeSelection(at: rows[1].id)
        model.extendRangeSelection(to: rows[3].id)

        #expect(model.listSelection == [rows[0].id, rows[4].id])
    }

    @Test("Moving the range back shrinks it and keeps the earlier selection")
    func rangeShrinks() {
        let rows = makeRows(5)
        let model = makeModel(rows)
        model.listSelection = [rows[0].id]

        model.beginRangeSelection(at: rows[2].id)
        model.extendRangeSelection(to: rows[4].id)
        model.extendRangeSelection(to: rows[3].id)

        #expect(model.listSelection == [rows[0].id, rows[2].id, rows[3].id])
    }

    @Test("A range can run upward and past its first row")
    func rangeRunsUpward() {
        let rows = makeRows(5)
        let model = makeModel(rows)

        model.beginRangeSelection(at: rows[2].id)
        model.extendRangeSelection(to: rows[0].id)
        #expect(model.listSelection == [rows[0].id, rows[1].id, rows[2].id])

        model.extendRangeSelection(to: rows[4].id)
        #expect(model.listSelection == [rows[2].id, rows[3].id, rows[4].id])
    }

    @Test("Ending the range keeps the selection and starts the next range fresh")
    func endingKeepsSelection() {
        let rows = makeRows(4)
        let model = makeModel(rows)

        model.beginRangeSelection(at: rows[0].id)
        model.extendRangeSelection(to: rows[1].id)
        model.endRangeSelection()
        #expect(!model.isRangeSelecting)
        #expect(model.listSelection == [rows[0].id, rows[1].id])

        // Row 1 is selected now, so the next range deselects.
        model.beginRangeSelection(at: rows[1].id)
        model.extendRangeSelection(to: rows[2].id)
        #expect(model.listSelection == [rows[0].id])
    }

    @Test("The pointer position maps to the row under it, or the nearest row in a gap or beyond the ends")
    func rowAtPosition() {
        let rows = makeRows(3)
        let model = makeModel(rows)
        model.rowFrames = [
            rows[0].id: CGRect(x: 0, y: 0, width: 100, height: 50),
            rows[1].id: CGRect(x: 0, y: 51, width: 100, height: 50),
            rows[2].id: CGRect(x: 0, y: 102, width: 100, height: 50),
        ]

        #expect(model.rowId(atY: 25) == rows[0].id)
        #expect(model.rowId(atY: 75) == rows[1].id)
        #expect(model.rowId(atY: 50.4) == rows[0].id)
        #expect(model.rowId(atY: -30) == rows[0].id)
        #expect(model.rowId(atY: 400) == rows[2].id)
    }

    @Test("Leaving selection mode ends a running range")
    func leavingSelectionModeEndsRange() {
        let rows = makeRows(2)
        let model = makeModel(rows, selectionMode: true)
        model.beginRangeSelection(at: rows[0].id)

        model.update(selectionMode: false)

        #expect(!model.isRangeSelecting)
    }

    private func makeModel(_ rows: [FolderListItemModel], selectionMode: Bool = true) -> FolderListModel {
        let model = FolderListModel(isSelectionMode: selectionMode, navigationModel: ModuleNavigationModel())
        model.list = rows
        return model
    }

    private func makeRows(_ count: Int) -> [FolderListItemModel] {
        (0..<count).map { _ in
            let id = UUID()
            return FolderListItemModel(id: id, source: ItemRowModel(itemId: id, typeId: .none), level: 0, isShown: false)
        }
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
