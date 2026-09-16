// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

public extension PhotoRootModel {
    static let previewPhotoId = PhotoModel.previewId
    static let previewPaladinPhotoId = PhotoModel.previewPaladinId
    static let previewWizardPhotoId = PhotoModel.previewRotatedId

    @MainActor
    static var preview: PhotoRootModel {
        previewFixture()
    }

    @MainActor
    internal static func previewFixture(
        models: [PhotoModel] = PhotoModel.previewFixtures
    ) -> PhotoRootModel {
        let root = PhotoRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))

        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }

        if let cacheController = root.itemController.cacheController {
            for (id, photo) in PhotoModel.previewAssetFixtures {
                guard let image = PreviewAssetFixture.image(photo) else { continue }
                cacheController.setCachedImage(image, for: id)
                cacheController.setCachedThumbnail(image, for: id)
            }
        }

        root.editController.setCurrentItem(to: .preview)
        return root
    }
    
    @MainActor
    static var previewWithData: PhotoRootModel {
        previewFixture()
    }
    
#if DEBUG
    @MainActor
    static func testRoot() -> PhotoRootModel {
        let root = PhotoRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

@MainActor
extension PhotoRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
}

// MARK: Preview - Test
extension PhotoModel {
    nonisolated static let previewId = UUID.fixture("12975503-CC29-4837-8018-EFF774E97595")
    nonisolated static let previewPaladinId = UUID(uuid: (0xB3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    nonisolated static let previewEmptyId = UUID(uuid: (0xB3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    nonisolated static let previewRotatedId = UUID(uuid: (0xB3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))

    @MainActor
    static var preview: PhotoModel {
        PhotoModel(
            id: previewId,
            name: "ExodusAtlantisMap",
            description: "Imaginary map of Atlantis for Amber DRPG \"Exodus\", a tabletop roleplaying game. Author: Theresa Thomas. From Wikimedia: [Wikipedia](https://commons.wikimedia.org/wiki/File:ExodusAtlantisMap.jpg)",
            tags: ["Map", "Fantasy"],
            degrees: 0,
            fileUrl: PreviewAssetFixture.photoFileUrl(
                .adventure,
                fileId: previewId,
                module: NetworkModules.photo.token
            ),
            entries: []
        )
    }

    @MainActor
    static var previewPaladin: PhotoModel {
        PhotoModel(
            id: previewPaladinId,
            name: "Paladin",
            description: "A player-character portrait used by previews and snapshots.",
            tags: ["Character", "Portrait"],
            fileUrl: PreviewAssetFixture.photoFileUrl(
                .paladin,
                fileId: previewPaladinId,
                module: NetworkModules.photo.token
            )
        )
    }

    @MainActor
    static var previewEmpty: PhotoModel {
        PhotoModel(
            id: previewEmptyId,
            name: "Empty Photo",
            description: "A photo fixture without an imported image.",
            tags: ["Preview"]
        )
    }

    @MainActor
    static var previewRotated: PhotoModel {
        PhotoModel(
            id: previewRotatedId,
            name: "Rotated Photo",
            description: "A portrait-orientation preview fixture.",
            tags: ["Preview", "Rotated"],
            degrees: 90,
            fileUrl: PreviewAssetFixture.photoFileUrl(
                .wizard,
                fileId: previewRotatedId,
                module: NetworkModules.photo.token
            )
        )
    }

    @MainActor
    static var previewFixtures: [PhotoModel] {
        [preview, previewPaladin, previewRotated, previewEmpty]
    }

    nonisolated static let previewAssetFixtures: [(UUID, PreviewAssetFixture.Photo)] = [
        (previewId, .adventure),
        (previewPaladinId, .paladin),
        (previewRotatedId, .wizard),
    ]
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: PhotoModel.previewId, typeId: .photo)
    @MainActor
    static var previewWithData: ItemRowTreeModel {
        let root = PhotoRootModel.previewWithData
        return ItemRowTreeModel(
            itemId: root.itemController.itemDataModel.items.first ?? PhotoModel.previewId,
            entryId: nil,
            typeId: .photo
        )
    }

}

extension ItemController {
    @MainActor
    static var preview: ItemController {
        PhotoRootModel.previewFixture().itemController
    }
}

extension EditController {
    @MainActor
    static var preview: EditController {
        let controller = PhotoRootModel.previewFixture().editController
        controller.setCurrentItem(to: .preview)
        return controller
    }
}

extension GameController {
    @MainActor
    static var preview: GameController {
        PhotoRootModel.previewFixture().gameController
    }
}

extension ImportController {
    @MainActor
    static var preview: ImportController {
        PhotoRootModel.previewFixture().importController
    }
}

extension ExportController {
    @MainActor
    static var preview: ExportController {
        PhotoRootModel.previewFixture().exportController
    }
}

extension ViewController {
    @MainActor
    static var preview: ViewController {
        PhotoRootModel.previewFixture().viewController
    }
}

extension LinkController {
    @MainActor
    static var preview: LinkController {
        PhotoRootModel.previewFixture().linkController
    }
}

private extension UUID {
    nonisolated static func fixture(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid deterministic preview UUID: \(value)")
        }
        return id
    }
}
