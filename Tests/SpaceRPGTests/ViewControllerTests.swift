// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import SpaceRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesAndCapabilities() {
        let root = SpaceRootModel.testRoot()
        let sut = ViewController()
        let itemId = UUID()
        let space = SpaceModel(id: itemId, name: "Viewer Space", displayState: 0)
        root.itemController.replace(model: space, isInsert: true)
        root.gameController.setGame(item: space, itemId: itemId)
        let source = ItemRowModel(itemId: itemId, typeId: .space)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.fileImporterView(for: itemId, preopen: true, layoutDown: true)
        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.gameListView(root: root)
        _ = sut.linkListView(type: .selection, itemSelectionModel: selectionModel)
        _ = sut.gameViewer(root: root)
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.windowViewer(root: root, selection: WindowItemSelection(itemId: itemId))

        #expect(sut.fileImporterViewType == .custom)
        #expect(sut.sharingViewType == .share)
        #expect(sut.thumbnailRowViewType == .photo)
    }
}
