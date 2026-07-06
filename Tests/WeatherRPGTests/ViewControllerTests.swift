// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG
@testable import WeatherRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesAndCapabilities() {
        let photoRoot = PhotoRootModel.testRoot()
        let root = WeatherRootModel.testRoot(photoRoot: photoRoot)
        let sut = WeatherRPG.ViewController()
        let itemId = UUID()
        let weather = WeatherModel.empty(itemId)
        weather.name = "Viewer Weather"
        root.itemController.replace(model: weather, isInsert: true)
        root.gameController.setGame(item: weather, itemId: itemId)
        let source = ItemRowModel(itemId: itemId, typeId: .weather)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.thumbnailRowView(for: itemId)
        _ = sut.thumbnailRowView(for: weather)
        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.photoSelection(root: root, selectionModel: selectionModel)
        _ = sut.gameListView(root: root)
        _ = sut.linkListView(type: .selection, itemSelectionModel: selectionModel)
        _ = sut.gameViewer(root: root)
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.windowViewer(root: root, selection: WindowItemSelection(itemId: itemId))

        #expect(sut.sharingViewType == .share)
        #expect(sut.thumbnailRowViewType == .custom)
    }
}
