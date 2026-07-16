// @copyright André Trettin

import AVFoundation
import CoreRPG
import Foundation
import RPGResources

public extension AudioRootModel {
    @MainActor
    static let preview: AudioRootModel = previewFixture()

    @MainActor
    internal static func previewFixture(
        models: [AudioModel] = AudioModel.previewFixtures,
        playlist: [PlaylistItem] = PlaylistItem.previewFixtures
    ) -> AudioRootModel {
        let root = AudioRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        root.audioPlayerModel.playList = playlist
        root.audioPlayerModel.currentItem = playlist.first
        root.audioPlayerModel.playerTime = PlayerTime(elapsedTime: 42, remainingTime: 138)
        root.audioPlayerModel.volume = 0.55
        return root
    }
    
    @MainActor
    static let previewWithData: AudioRootModel = {
        let root = AudioRootModel.preview
        let importController = root.importController
        let editController = root.editController
#if DEBUG
        Task(priority: .userInitiated) {
            let bundle = RPGResources.Resources.bundle
            guard let url = bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try? await task.value
            Task { @MainActor in
                editController.setCurrentItem(to: .previewWithData)
            }
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot() -> AudioRootModel {
        let root = AudioRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

@MainActor
extension AudioRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
}

// MARK: Preview - Test
extension AudioModel {
    nonisolated static let previewId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x21))
    nonisolated static let previewAmbientId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x22))
    nonisolated static let previewEmptyId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x23))

    @MainActor
    static let preview = AudioModel(
        id: previewId,
        name: "Storm over Emberkeep",
        description: "A dramatic soundtrack for the final encounter.",
        tags: ["Combat", "Orchestral"]
    )

    @MainActor
    static var previewFixtures: [AudioModel] {
        [
            AudioModel(
                id: previewId,
                name: "Storm over Emberkeep",
                description: "A dramatic soundtrack for the final encounter.",
                tags: ["Combat", "Orchestral"]
            ),
            AudioModel(
                id: previewAmbientId,
                name: "Rain in the Old Forest",
                description: "Quiet ambience for exploration.",
                tags: ["Ambient"]
            ),
            AudioModel(id: previewEmptyId, name: "Audio without File")
        ]
    }
}

extension PlaylistItem {
    static var previewFixtures: [PlaylistItem] {
        [
            PlaylistItem(
                id: AudioModel.previewId,
                url: URL(filePath: "/tmp/masterrpg-preview-storm.m4a"),
                title: "Storm over Emberkeep",
                artist: "MasterRPG Preview",
                duration: CMTime(seconds: 180, preferredTimescale: 600)
            ),
            PlaylistItem(
                id: AudioModel.previewAmbientId,
                url: URL(filePath: "/tmp/masterrpg-preview-rain.m4a"),
                title: "Rain in the Old Forest",
                artist: "MasterRPG Preview",
                duration: CMTime(seconds: 240, preferredTimescale: 600)
            )
        ]
    }
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: AudioModel.previewId, typeId: .audio)
    @MainActor
    static var previewWithData: ItemRowTreeModel = {
        let root = AudioRootModel.previewWithData
        return ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .audio)
    }()
}

extension ItemController {
    @MainActor
    static var preview = AudioRootModel.preview.itemController
    }

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = AudioRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = AudioRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = AudioRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = AudioRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static var preview = AudioRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = AudioRootModel.preview.linkController
}
