// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.folderListController
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? AudioRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? AudioDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? AudioDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? AudioRoute) == .detail(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
