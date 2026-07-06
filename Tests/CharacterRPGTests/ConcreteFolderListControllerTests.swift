// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import DiceRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let root = CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let sut = try #require(root.folderListController as? CharacterRPG.FolderListController)
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? CharacterRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? CharacterDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? CharacterDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? CharacterRPG.DetailRoute) == .viewer(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
