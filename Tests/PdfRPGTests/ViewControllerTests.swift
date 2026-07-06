// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import PdfRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesAndCapabilities() {
        let root = PdfRootModel.testRoot()
        let sut = ViewController()
        let itemId = UUID()
        let pdf = PdfModel(id: itemId, name: "Viewer PDF")
        root.itemController.replace(model: pdf, isInsert: true)
        root.gameController.setGame(item: pdf, itemId: itemId)
        let source = ItemRowModel(itemId: itemId, typeId: .pdf)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.linkListView(type: .inspector, itemSelectionModel: selectionModel)
        _ = sut.viewer(root: root, itemId: itemId, entryId: nil, configuration: ViewerConfiguration(canBookmark: true), onTextExtracted: { _ in }, dismissAction: {})
        _ = sut.gameView(root: root)
        _ = sut.gamePdfView(root: root)

        #expect(sut.sharingViewType == .share)
        #expect(sut.thumbnailRowViewType == .photo)
    }
}
