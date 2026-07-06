// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let root = PhotoRootModel.testRoot()
        let sut = try #require(root.folderListController as? FolderListController)
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? PhotoRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? PhotoDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? PhotoDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? PhotoRPG.DetailRoute) == .viewer(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
