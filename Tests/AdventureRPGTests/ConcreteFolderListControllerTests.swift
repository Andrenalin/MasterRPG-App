// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import AudioRPG
@testable import CharacterRPG
@testable import DiceRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import TableRPG
@testable import WeatherRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let audioRoot = AudioRootModel.testRoot()
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let spaceRoot = SpaceRootModel.testRoot()
        let weatherRoot = WeatherRootModel.testRoot(photoRoot: photoRoot)
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let characterRoot = CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let mapRoot = MapRootModel.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)
        let root = AdventureRootModel.testRoot(audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
        let sut = root.folderListController
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? AdventureRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? AdventureDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? AdventureDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? AdventureRPG.DetailRoute) == .viewer(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
