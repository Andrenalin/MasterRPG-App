// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import PdfRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let root = PdfRootModel.testRoot()
        let sut = try #require(root.folderListController as? FolderListController)
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? PdfRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? PdfDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? PdfDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? PdfRPG.DetailRoute) == .viewer(itemId, nil))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
