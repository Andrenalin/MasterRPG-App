// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Folder list navigation state")
struct FolderListNavigationStateTests {
    @Test("Returning to a module restores its last user scroll target")
    func restoresLastUserScrollTarget() {
        // Given
        let first = makeRow(name: "First")
        let middle = makeRow(name: "Middle")
        let last = makeRow(name: "Last")
        let model = FolderListModel(navigationModel: ModuleNavigationModel())
        model.list = [first, middle, last]
        model.selected = first.id
        model.recordVisibleScrollPosition(middle.id)

        // When
        let target = model.restoredScrollTarget(selection: model.selected)

        // Then
        #expect(target == middle.id)
    }

    @Test("An active search prioritizes its selected result")
    func searchPrioritizesSelection() {
        // Given
        let first = makeRow(name: "First")
        let searchResult = makeRow(name: "Search result")
        let model = FolderListModel(navigationModel: ModuleNavigationModel())
        model.list = [first, searchResult]
        model.recordVisibleScrollPosition(first.id)

        // When
        let target = model.restoredScrollTarget(
            selection: searchResult.id,
            prioritizesSelection: true
        )

        // Then
        #expect(target == searchResult.id)
    }

    @Test("A removed saved row falls back to the selected row")
    func missingSavedRowFallsBackToSelection() {
        // Given
        let removed = makeRow(name: "Removed")
        let selected = makeRow(name: "Selected")
        let model = FolderListModel(navigationModel: ModuleNavigationModel())
        model.list = [removed, selected]
        model.recordVisibleScrollPosition(removed.id)
        model.list = [selected]

        // When
        let target = model.restoredScrollTarget(selection: selected.id)

        // Then
        #expect(target == selected.id)
    }

    @Test("The selected folder toggles open and closed")
    func togglesSelectedFolder() {
        // Given
        let folder = makeRow(name: "Folder")
        folder.children = [makeRow(name: "Child")]
        let model = FolderListModel(navigationModel: ModuleNavigationModel())
        model.list = [folder]
        model.selected = folder.id
        let controller = FakeFolderListController(listModel: model)

        // When
        let opened = controller.toggleSelectedFolder()
        let isOpen = folder.isOpen
        let closed = controller.toggleSelectedFolder()

        // Then
        #expect(opened)
        #expect(isOpen)
        #expect(closed)
        #expect(!folder.isOpen)
        #expect(model.lastNonNilScrollId == folder.id)
    }
}

private extension FolderListNavigationStateTests {
    func makeRow(name: String) -> FolderListItemModel {
        let id = UUID()
        return FolderListItemModel(
            id: id,
            source: ItemRowModel(itemId: id, typeId: .none),
            destination: nil,
            level: 0,
            isShown: false
        )
    }
}
