// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import PhotoRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesAndCapabilities() {
        let root = PhotoRootModel.testRoot()
        let sut = ViewController()
        let itemId = UUID()
        let photo = PhotoModel(id: itemId, name: "Viewer Photo")
        root.itemController.replace(model: photo, isInsert: true)
        root.gameController.setGame(item: photo, itemId: itemId)
        let source = ItemRowModel(itemId: itemId, typeId: .photo)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.fileImporterView(for: itemId, preopen: true, layoutDown: false)
        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.dropSelectionView(model: selectionModel)
        _ = sut.thumbnailRow(root: root, for: itemId, listDisplayModel: ListDisplayModel())
        _ = sut.photoRow(root: root, for: itemId)
        _ = sut.carouselPhotos(root: root, photoSelection: selectionModel)
        _ = sut.gameListView(root: root)
        _ = sut.linkListView(type: .selection, itemSelectionModel: selectionModel)
        _ = sut.gameViewer(root: root)
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.windowViewer(root: root, selection: WindowItemSelection(itemId: itemId))
        _ = sut.mapImage(root: root, for: itemId, size: CGSize(width: 80, height: 60), color: .red)
        _ = sut.photoDetailView(root: root, for: itemId, size: CGSize(width: 80, height: 60), contentMode: .fill)

        #expect(sut.fileImporterViewType == .custom)
        #expect(sut.sharingViewType == .share)
        #expect(sut.thumbnailRowViewType == .photo)
    }
}
