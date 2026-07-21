// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import AudioRPG
@testable import CharacterRPG
@testable import DiceRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesGameBranchesAndBatchExtraction() {
        let roots = makeRoots()
        let root = roots.map
        let sut = MapRPG.ViewController()
        let itemId = UUID()
        let playerId = UUID()
        let newPlayerId = UUID()
        let map = MapModel(
            id: itemId,
            name: "Viewer Map",
            mapPins: [MapPinModel(id: playerId, name: "Old Player", location: CGPoint(x: 1, y: 1), timeInterval: 1)]
        )
        root.itemController.replace(model: map, isInsert: true)
        root.gameController.setGame(item: map, itemId: itemId)
        root.gameController.mapGameModel.playerPins = [
            MapPinModel(id: playerId, name: "Player", location: CGPoint(x: 4, y: 4), isPlayer: true, timeInterval: 2),
            MapPinModel(id: newPlayerId, name: "New Player", location: CGPoint(x: 8, y: 8), isPlayer: true, timeInterval: 3)
        ]
        let source = ItemRowModel(itemId: itemId, typeId: .map)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.thumbnailRowView(for: itemId)
        _ = sut.thumbnailRowView(for: map)
        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.batchExtractionView(itemController: root.itemController, editController: root.editController, ids: [itemId])
        _ = sut.batchExtractionView(itemController: roots.dice.itemController, editController: root.editController, ids: [itemId])
        _ = sut.characterSelection(root: root, selectionModel: selectionModel)
        _ = sut.diceSelection(root: root, selectionModel: selectionModel)
        _ = sut.photoSelection(root: root, selectionModel: selectionModel)
        _ = sut.linkListView(type: .inspector, itemSelectionModel: selectionModel)
        _ = sut.windowViewer(root: root, selection: WindowItemSelection(itemId: itemId))
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.mapEditWindow(root: root)
        _ = sut.mapEditWindow(root: root, isTileEditor: true)
        _ = sut.gameView(root: root)
        _ = sut.gameMapView(root: root, playerId: playerId)
        _ = sut.gameMasterMapView(root: root, id: itemId)
        _ = sut.gameMasterMapView(root: root, id: nil)
        _ = sut.gameToolBarView(root: root, isMaster: true)

        let gameMap = root.gameController.gameItem(for: itemId)
        #expect(gameMap.mapPins.first { $0.id == playerId }?.location == CGPoint(x: 1, y: 1))
        #expect(!gameMap.mapPins.contains { $0.id == newPlayerId })

        #expect(root.gameController.synchronizePlayerPins(for: itemId))
        #expect(gameMap.mapPins.contains { $0.id == playerId && $0.location == CGPoint(x: 4, y: 4) })
        #expect(gameMap.mapPins.first { $0.id == newPlayerId }?.location == .zero)
        #expect(!root.gameController.synchronizePlayerPins(for: itemId))
        #expect(sut.sharingViewType == .share)
        #expect(sut.thumbnailRowViewType == .custom)
        #expect(sut.supportsBatchExtraction)
    }

    private func makeRoots() -> (
        audio: AudioRootModel,
        dice: DiceRootModel,
        pdf: PdfRootModel,
        photo: PhotoRootModel,
        table: TableRootModel,
        character: CharacterRootModel,
        map: MapRootModel
    ) {
        let audioRoot = AudioRootModel.testRoot()
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
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
        return (audioRoot, diceRoot, pdfRoot, photoRoot, tableRoot, characterRoot, mapRoot)
    }
}
