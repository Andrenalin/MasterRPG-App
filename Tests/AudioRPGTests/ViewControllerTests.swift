// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import AudioRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesCapabilitiesAndPlayerBridges() async throws {
        let root = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = ViewController()
        let itemId = UUID()
        let audio = AudioModel(id: itemId, name: "Viewer Audio")
        root.itemController.replace(model: audio, isInsert: true)
        let source = ItemRowModel(itemId: itemId, typeId: .audio)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.sharingView(for: itemId)
        _ = sut.thumbnailRowView(for: itemId)
        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.linkListView(type: .inspector, itemSelectionModel: selectionModel)
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.gameView(root: root)
        _ = sut.viewAudioPlayer(root: root, with: itemId)
        _ = sut.menuAudioPlayer(root: root, with: itemId)
        _ = sut.viewVolume(root: root, alignment: .bottomTrailing)

        try await root.gameController.play(id: nil, shouldPlay: true)

        #expect(sut.sharingViewType == .custom)
        #expect(sut.thumbnailRowViewType == .custom)
        #expect(sut.hasCustomSpaceAction)
    }
}
