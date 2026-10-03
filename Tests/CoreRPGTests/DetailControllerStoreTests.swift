// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_Folder §8.1: a detail route keeps its list controller across body evaluations.
@Suite("Detail controller store")
@MainActor
struct DetailControllerStoreTests {
    private func makeController(parent: FakeItemModel) -> FakeFolderListController {
        FakeFolderListController(listModel: FolderListModel(parentModel: parent, navigationModel: ModuleNavigationModel()))
    }

    @Test("The same item in the same folder keeps its controller and list state")
    func sameRouteKeepsController() {
        let store = DetailControllerStore<FakeFolderListController>()
        let itemId = UUID()
        let parent = FakeItemModel(name: "Folder", category: .folder)
        var made = 0
        let first = store.controller(itemId: itemId, parentModel: parent) {
            made += 1
            return makeController(parent: parent)
        }
        first.listModel.selected = UUID()

        // A sync replaced the folder's instance.
        let replacedParent = FakeItemModel(id: parent.id, name: "Folder renamed", category: .folder)
        let second = store.controller(itemId: itemId, parentModel: replacedParent) {
            made += 1
            return makeController(parent: replacedParent)
        }

        #expect(made == 1)
        #expect(second.listModel === first.listModel)
        #expect(second.listModel.selected == first.listModel.selected)
        #expect(second.listModel.parentModel?.name == "Folder renamed")
    }

    @Test("Another item or another folder gets a new controller")
    func otherRouteGetsNewController() {
        let store = DetailControllerStore<FakeFolderListController>()
        let parent = FakeItemModel(name: "Folder", category: .folder)
        let otherParent = FakeItemModel(name: "Other", category: .folder)
        let itemId = UUID()
        let first = store.controller(itemId: itemId, parentModel: parent) { makeController(parent: parent) }

        let otherItem = store.controller(itemId: UUID(), parentModel: parent) { makeController(parent: parent) }
        let otherFolder = store.controller(itemId: itemId, parentModel: otherParent) { makeController(parent: otherParent) }

        #expect(otherItem.listModel !== first.listModel)
        #expect(otherFolder.listModel !== otherItem.listModel)
        #expect(otherFolder.listModel.parentModel?.id == otherParent.id)
    }
}
