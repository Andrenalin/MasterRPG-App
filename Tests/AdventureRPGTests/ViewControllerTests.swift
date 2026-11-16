// @copyright André Trettin

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
struct ViewControllerTests {
    @Test func viewFactoriesGameBranchesAndBatchExtraction() {
        let roots = makeRoots()
        let root = roots.adventure
        let sut = AdventureRPG.ViewController()
        let itemId = UUID()
        let adventure = AdventureModel(id: itemId, name: "Viewer Adventure")
        root.itemController.replace(model: adventure, isInsert: true)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.thumbnailRowView(for: itemId)
        _ = sut.thumbnailRowView(for: adventure)
        _ = sut.batchExtractionView(itemController: root.itemController, editController: root.editController, ids: [itemId])
        _ = sut.batchExtractionView(itemController: roots.dice.itemController, editController: root.editController, ids: [itemId])
        _ = sut.dropChooseView(model: selectionModel)
        _ = sut.linkListView(type: .selection, itemSelectionModel: selectionModel)
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.gameView(root: root, focusedIds: [itemId])
        _ = sut.gameView(root: root, focusedIds: [])
        _ = sut.gameModuleListView(root: root, isPlayer: true)
        _ = sut.gameModuleListView(root: root, isPlayer: false)

        #expect(sut.thumbnailRowViewType == .custom)
        #expect(sut.supportsBatchExtraction)
    }

    private func makeRoots() -> (
        audio: AudioRootModel,
        dice: DiceRootModel,
        map: MapRootModel,
        pdf: PdfRootModel,
        photo: PhotoRootModel,
        space: SpaceRootModel,
        table: TableRootModel,
        character: CharacterRootModel,
        weather: WeatherRootModel,
        adventure: AdventureRootModel
    ) {
        let audioRoot = AudioRootModel.testRoot()
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let spaceRoot = SpaceRootModel.testRoot()
        let weatherRoot = WeatherRootModel.testRoot(photoRoot: photoRoot)
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let characterRoot = CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let mapRoot = MapRootModel.testRoot(
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            tableRoot: tableRoot,
            characterRoot: characterRoot
        )
        let adventureRoot = AdventureRootModel.testRoot(
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            characterRoot: characterRoot,
            weatherRoot: weatherRoot
        )
        return (audioRoot, diceRoot, mapRoot, pdfRoot, photoRoot, spaceRoot, tableRoot, characterRoot, weatherRoot, adventureRoot)
    }
}
