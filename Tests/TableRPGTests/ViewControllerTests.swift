// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG
@testable import PdfRPG
@testable import TableRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesCapabilitiesAndBatchExtraction() {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let root = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let sut = TableRPG.ViewController()
        let itemId = UUID()
        let table = TableModel(id: itemId, name: "Viewer Table", entries: [])
        root.itemController.replace(model: table, isInsert: true)
        root.gameController.setGame(item: table, itemId: itemId)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.thumbnailRowView(for: itemId)
        _ = sut.thumbnailRowView(for: table)
        _ = sut.gameListView(root: root)
        _ = sut.linkListView(type: .selection, itemSelectionModel: selectionModel)
        _ = sut.batchExtractionView(itemController: root.itemController, editController: root.editController, ids: [itemId])
        _ = sut.batchExtractionView(itemController: diceRoot.itemController, editController: root.editController, ids: [itemId])
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.windowViewer(root: root, selection: WindowItemSelection(itemId: itemId))
        _ = sut.gameViewer(root: root)

        #expect(sut.sharingViewType == .custom)
        #expect(sut.thumbnailRowViewType == .custom)
        #expect(sut.supportsBatchExtraction)
    }
}
