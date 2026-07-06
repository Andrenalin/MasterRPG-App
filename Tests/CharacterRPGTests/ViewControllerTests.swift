// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import DiceRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesAndGameBranches() {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let root = CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let sut = CharacterRPG.ViewController()
        let itemId = UUID()
        let value = ValueModel(id: itemId, name: "Viewer Character")
        root.itemController.replace(model: value, isInsert: true)
        let source = ItemRowModel(itemId: itemId, typeId: .value)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.thumbnailRowView(for: itemId)
        _ = sut.thumbnailRowView(for: value)
        _ = sut.diceSelection(root: root, selectionModel: selectionModel)
        _ = sut.linkListView(type: .inspector, itemSelectionModel: selectionModel)
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.dropChooseView(model: selectionModel)
        _ = sut.gameView(root: root, select: itemId)
        _ = sut.gameView(root: root)

        #expect(sut.thumbnailRowViewType == .custom)
    }
}
