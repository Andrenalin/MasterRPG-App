// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let root = GeneratorRootModel.testRoot()
        let sut = root.folderListController
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? GeneratorRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? GeneratorDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? GeneratorDetailRoute) == .folder(itemId))
        #expect((sut.viewerDestination(for: itemId) as? GeneratorRPG.DetailRoute) == .viewer(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
