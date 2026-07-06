// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let root = DiceRootModel.testRoot()
        let sut = try #require(root.folderListController as? FolderListController)
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? DiceRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? DiceDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? DiceDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? DiceRoute) == .detail(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
