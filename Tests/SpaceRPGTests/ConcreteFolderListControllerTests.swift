// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import SpaceRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let root = SpaceRootModel.testRoot()
        let sut = root.folderListController
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? SpaceRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? SpaceDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? SpaceDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? SpaceRPG.DetailRoute) == .viewer(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
