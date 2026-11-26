// @copyright André Trettin

import Foundation
import SwiftUI
import Testing

@testable import CoreRPG

/// Select All / Select None of the module list in selection mode.
@MainActor
@Suite("Folder list select all")
struct FolderListSelectAllTests {
    @Test("Select All selects every row, Select None clears the selection")
    func selectsAllAndNone() {
        let rows = (0..<4).map { _ in makeRow() }
        let model = makeModel(rows)

        model.selectAllRows()
        #expect(model.listSelection == Set(rows.map(\.id)))

        model.selectNoRows()
        #expect(model.listSelection.isEmpty)
    }

    @Test("Select All ends a running range selection")
    func endsRangeSelection() {
        let rows = (0..<3).map { _ in makeRow() }
        let model = makeModel(rows)
        model.beginRangeSelection(at: rows[0].id)

        model.selectAllRows()

        #expect(!model.isRangeSelecting)
    }

    @Test("The rows under a folder are the rows one level deeper up to the next row at its level")
    func childRows() {
        let folder = makeRow(level: 0)
        let first = makeRow(level: 1)
        let nested = makeRow(level: 1)
        let nestedChild = makeRow(level: 2)
        let last = makeRow(level: 1)
        let other = makeRow(level: 0)
        let model = makeModel([folder, first, nested, nestedChild, last, other])

        #expect(model.childRowIds(of: folder.id) == [first.id, nested.id, last.id])
        #expect(model.childRowIds(of: nested.id) == [nestedChild.id])
        #expect(model.childRowIds(of: other.id).isEmpty)
        #expect(model.childRowIds(of: UUID()).isEmpty)
    }

    @Test("In folder mode on an open folder Select All selects the items in it")
    func folderModeSelectsFolderItems() {
        let controller = ItemRootController.fake.folderListControllable
        let folder = makeRow(level: 0, isOpen: true)
        let first = makeRow(level: 1)
        let second = makeRow(level: 1)
        let other = makeRow(level: 0)
        controller.listModel.list = [folder, first, second, other]
        controller.listDisplayModel.isFolderMode = true

        controller.selectAll(in: controller.listModel, anchorRowId: folder.id)

        #expect(controller.listModel.listSelection == [first.id, second.id])
    }

    @Test("The context menu names the folder only in folder mode on a folder row")
    func selectAllFolderRow() {
        let controller = ItemRootController.fake.folderListControllable
        let folder = makeRow(level: 0, isOpen: true)
        let child = makeRow(level: 1)
        let plain = makeRow(level: 0)
        controller.listModel.list = [folder, child, plain]
        controller.listDisplayModel.isFolderMode = true

        #expect(controller.selectAllFolderRow(in: controller.listModel, anchorRowId: folder.id)?.id == folder.id)
        #expect(controller.selectAllFolderRow(in: controller.listModel, anchorRowId: plain.id) == nil)
        #expect(controller.selectAllFolderRow(in: controller.listModel, anchorRowId: nil) == nil)


        let detail = FolderListModel(isSelectionMode: true, navigationModel: ModuleNavigationModel())
        detail.list = [folder]
        #expect(controller.selectAllFolderRow(in: detail, anchorRowId: folder.id) == nil)
    }

    @Test("The row the context menu was opened on decides the folder, not the keyboard row")
    func contextRowDecides() {
        let controller = ItemRootController.fake.folderListControllable
        let first = makeRow(level: 0, isOpen: true)
        let firstChild = makeRow(level: 1)
        let second = makeRow(level: 0, isOpen: true)
        let secondChild = makeRow(level: 1)
        controller.listModel.list = [first, firstChild, second, secondChild]
        controller.listModel.keyboardRowId = first.id
        controller.listDisplayModel.isFolderMode = true

        controller.selectAll(in: controller.listModel, anchorRowId: second.id)

        #expect(controller.listModel.listSelection == [secondChild.id])
    }

    @Test("In folder mode on a plain item Select All selects every row")
    func folderModeOnItemSelectsAll() {
        let controller = ItemRootController.fake.folderListControllable
        let rows = [makeRow(level: 0, isOpen: true), makeRow(level: 1), makeRow(level: 0)]
        controller.listModel.list = rows
        controller.listDisplayModel.isFolderMode = true

        controller.selectAll(in: controller.listModel, anchorRowId: rows[2].id)

        #expect(controller.listModel.listSelection == Set(rows.map(\.id)))
    }

    @Test("A folder item is named in both list modes, a plain item is not")
    func folderNameInBothModes() {
        let controller = ItemRootController.fake.folderListControllable
        let folder = makeRow(level: 0)
        folder.model = FakeItemModel(name: "Dungeon", category: .folder)
        let plain = makeRow(level: 0)
        plain.model = FakeItemModel(name: "Goblin", category: .photo)
        controller.listModel.list = [folder, plain]

        controller.listDisplayModel.isListMode = true
        #expect(controller.selectAllFolderName(in: controller.listModel, anchorRowId: folder.id) == "Dungeon")
        #expect(controller.selectAllFolderName(in: controller.listModel, anchorRowId: plain.id) == nil)

        controller.listDisplayModel.isFolderMode = true
        #expect(controller.selectAllFolderName(in: controller.listModel, anchorRowId: folder.id) == "Dungeon")
        #expect(controller.selectAllFolderName(in: controller.listModel, anchorRowId: plain.id) == nil)
    }

    @Test("The menu bar entry names the folder of the keyboard row")
    func menuBarNamesFolder() {
        let root = ItemRootController.fake
        let controller = root.folderListControllable
        let folder = makeRow(level: 0)
        folder.model = FakeItemModel(name: "Dungeon", category: .folder)
        controller.listModel.list = [folder]
        controller.listModel.keyboardRowId = folder.id
        controller.listDisplayModel.isSelectionMode = true

        let actions = ListSelectionMenuPolicy.resolved(focused: nil, root: root)
        #expect(actions.selectAllFolderName() == "Dungeon")

        controller.listModel.keyboardRowId = nil
        #expect(ListSelectionMenuPolicy.resolved(focused: nil, root: root).selectAllFolderName() == nil)

        // The same actions follow the keyboard row without being rebuilt.
        controller.listModel.keyboardRowId = folder.id
        #expect(actions.selectAllFolderName() == "Dungeon")
        controller.listModel.keyboardRowId = nil
        #expect(actions.selectAllFolderName() == nil)
        controller.listDisplayModel.isSelectionMode = false
    }

    @Test("In list mode a folder row is just a row: Select All selects every row")
    func listModeSelectsAll() {
        let controller = ItemRootController.fake.folderListControllable
        let rows = [makeRow(level: 0, isOpen: true), makeRow(level: 1), makeRow(level: 0)]
        controller.listModel.list = rows
        controller.listDisplayModel.isListMode = true

        controller.selectAll(in: controller.listModel, anchorRowId: rows[0].id)

        #expect(controller.listModel.listSelection == Set(rows.map(\.id)))
    }

    @Test("Without a keyboard row Select All selects every row")
    func withoutAnchor() {
        let controller = ItemRootController.fake.folderListControllable
        let rows = [makeRow(level: 0, isOpen: true), makeRow(level: 1)]
        controller.listModel.list = rows
        controller.listDisplayModel.isFolderMode = true

        controller.selectAll(in: controller.listModel, anchorRowId: nil)

        #expect(controller.listModel.listSelection == Set(rows.map(\.id)))
    }

    @Test("Select None keeps selection mode and empties the selection")
    func selectNoneInController() {
        let controller = ItemRootController.fake.folderListControllable
        let rows = [makeRow(), makeRow()]
        controller.listModel.list = rows
        controller.listModel.listSelection = Set(rows.map(\.id))

        controller.selectNone(in: controller.listModel)

        #expect(controller.listModel.listSelection.isEmpty)
    }

    #if !os(tvOS)
    @Test("The commands are enabled only for a list in selection mode")
    func menuEnablement() {
        let inSelection = FocusedListSelectionActions(isSelectionMode: true, selectAll: {}, selectNone: {})
        let outside = FocusedListSelectionActions(isSelectionMode: false, selectAll: {}, selectNone: {})

        #expect(ListSelectionMenuPolicy.isEnabled(inSelection))
        #expect(!ListSelectionMenuPolicy.isEnabled(outside))
        #expect(!ListSelectionMenuPolicy.isEnabled(nil))
    }

    @Test("The menu bar's Select All selects the rows in selection mode and the text otherwise")
    func menuBarSelectAllFallsBackToText() {
        var calls: [String] = []
        let inSelection = FocusedListSelectionActions(isSelectionMode: true, selectAll: { calls.append("rows") }, selectNone: {})
        let outside = FocusedListSelectionActions(isSelectionMode: false, selectAll: { calls.append("rows") }, selectNone: {})

        ListSelectionMenuPolicy.performSelectAll(inSelection) { calls.append("text") }
        ListSelectionMenuPolicy.performSelectAll(outside) { calls.append("text") }
        ListSelectionMenuPolicy.performSelectAll(nil) { calls.append("text") }

        #expect(calls == ["rows", "text", "text"])
    }

    @Test("Select All is Command-A, Select None does not take Command-Shift-A (Add into folder)")
    func shortcuts() {
        #expect(ListSelectionMenuPolicy.selectAllKey == "a")
        #expect(ListSelectionMenuPolicy.selectAllModifiers == .command)
        #expect(ListSelectionMenuPolicy.selectNoneModifiers != [.command, .shift])
        #expect(ListSelectionMenuPolicy.selectNoneModifiers != ListSelectionMenuPolicy.selectAllModifiers)
    }

    @Test("Without a focused list the commands act on the root list and read its selection mode")
    func rootListFallback() {
        let root = ItemRootController.fake
        let controller = root.folderListControllable
        let rows = [makeRow(), makeRow(), makeRow()]
        controller.listModel.list = rows
        controller.listDisplayModel.isSelectionMode = false

        let off = ListSelectionMenuPolicy.resolved(focused: nil, root: root)
        #expect(!ListSelectionMenuPolicy.isEnabled(off))

        controller.listDisplayModel.isSelectionMode = true
        let on = ListSelectionMenuPolicy.resolved(focused: nil, root: root)
        #expect(ListSelectionMenuPolicy.isEnabled(on))

        on.selectAll()
        #expect(controller.listModel.listSelection == Set(rows.map(\.id)))
        on.selectNone()
        #expect(controller.listModel.listSelection.isEmpty)
        controller.listDisplayModel.isSelectionMode = false
    }

    @Test("A focused list's own actions are used, and either list's selection mode enables them")
    func focusedActionsWin() {
        let root = ItemRootController.fake
        root.folderListControllable.listDisplayModel.isSelectionMode = false
        var calls: [String] = []
        let focused = FocusedListSelectionActions(isSelectionMode: true, selectAll: { calls.append("all") }, selectNone: { calls.append("none") })

        let resolved = ListSelectionMenuPolicy.resolved(focused: focused, root: root)
        resolved.selectAll()
        resolved.selectNone()

        #expect(ListSelectionMenuPolicy.isEnabled(resolved))
        #expect(calls == ["all", "none"])
    }

    @Test("The command sets run the list's actions")
    func actionsRun() {
        var calls: [String] = []
        let actions = FocusedListSelectionActions(
            isSelectionMode: true,
            selectAll: { calls.append("all") },
            selectNone: { calls.append("none") }
        )

        actions.selectAll()
        actions.selectNone()

        #expect(calls == ["all", "none"])
    }
    #endif

    // MARK: - Helpers

    private func makeModel(_ rows: [FolderListItemModel]) -> FolderListModel {
        let model = FolderListModel(isSelectionMode: true, navigationModel: ModuleNavigationModel())
        model.list = rows
        return model
    }

    private func makeRow(level: Int = 0, isOpen: Bool = false) -> FolderListItemModel {
        let id = UUID()
        return FolderListItemModel(id: id, source: ItemRowModel(itemId: id, typeId: .none), level: level, isShown: isOpen)
    }
}
