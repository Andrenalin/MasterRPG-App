// @copyright André Trettin

import AVFoundation
import CoreRPG
import Foundation

public extension AudioRootModel {
    @MainActor
    static var preview: AudioRootModel { previewFixture() }

    @MainActor
    internal static func previewFixture(
        models: [AudioModel] = AudioModel.previewFixtures,
        playlist: [PlaylistItem] = PlaylistItem.previewFixtures
    ) -> AudioRootModel {
        let root = AudioRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
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
    static var previewWithData: AudioRootModel { previewFixture() }
    
#if DEBUG
    @MainActor
    static func testRoot() -> AudioRootModel {
        let root = AudioRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
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
        tags: ["Combat", "Orchestral"],
        fileUrl: PreviewAssetFixture.fileUrl(
            .audio,
            fileId: previewId,
            module: NetworkModules.audio.token
        )
    )

    @MainActor
    static var previewFixtures: [AudioModel] {
        [
            AudioModel(
                id: previewId,
                name: "Storm over Emberkeep",
                description: "A dramatic soundtrack for the final encounter.",
                tags: ["Combat", "Orchestral"],
                fileUrl: PreviewAssetFixture.fileUrl(
                    .audio,
                    fileId: previewId,
                    module: NetworkModules.audio.token
                )
            ),
            AudioModel(
                id: previewAmbientId,
                name: "Rain in the Old Forest",
                description: "Quiet ambience for exploration.",
                tags: ["Ambient"],
                fileUrl: PreviewAssetFixture.fileUrl(
                    .audio,
                    fileId: previewAmbientId,
                    module: NetworkModules.audio.token
                )
            ),
            AudioModel(id: previewEmptyId, name: "Audio without File")
        ]
    }
}

extension PlaylistItem {
    static var previewFixtures: [PlaylistItem] {
        let audioUrl = PreviewAssetFixture.url(.audio)
            ?? URL.temporaryDirectory.appending(path: "masterrpg-preview-audio.mp3")
        return [
            PlaylistItem(
                id: AudioModel.previewId,
                url: audioUrl,
                title: "Storm over Emberkeep",
                subtitle: "MasterRPG Preview",
                duration: CMTime(seconds: 180, preferredTimescale: 600)
            ),
            PlaylistItem(
                id: AudioModel.previewAmbientId,
                url: audioUrl,
                title: "Rain in the Old Forest",
                subtitle: "MasterRPG Preview",
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
