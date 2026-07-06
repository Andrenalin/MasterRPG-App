// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG
@testable import PdfRPG
@testable import TableRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let root = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let sut = try #require(root.folderListController as? TableRPG.FolderListController)
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? TableRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? TableDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? TableDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? TableRPG.DetailRoute) == .viewer(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
