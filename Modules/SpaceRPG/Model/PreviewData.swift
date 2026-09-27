// @copyright André Trettin

import CoreRPG
import Foundation

public extension SpaceRootModel {
    static let previewSpaceId = SpaceModel.previewId
    
    @MainActor
    static var preview: SpaceRootModel { previewFixture() }

    @MainActor
    internal static func previewFixture(
        models: [SpaceModel] = SpaceModel.previewFixtures
    ) -> SpaceRootModel {
        let root = SpaceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        return root
    }
    
    @MainActor
    static var previewWithData: SpaceRootModel { previewFixture() }
    
#if DEBUG
    @MainActor
    static func testRoot() -> SpaceRootModel {
        let root = SpaceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

@MainActor
extension SpaceRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
}

// MARK: Preview - Test
extension SpaceModel {
    nonisolated static let previewId = UUID.fixture("F5AC90DF-36F2-4151-B283-F0CF9D0BAC35")
    nonisolated static let previewEmptyId = UUID(uuid: (0xB4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    nonisolated static let previewRotatedId = UUID(uuid: (0xB4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))

    static var preview: SpaceModel {
        SpaceModel(
            id: previewId,
            name: "Ancient Relic",
            description: "A real USDZ object used by the 3D viewer preview.",
            tags: ["3D", "Artifact"],
            displayState: 0,
            degrees: 0,
            fileUrl: PreviewAssetFixture.fileUrl(
                .space,
                fileId: previewId,
                module: NetworkModules.space.token
            ),
            entries: []
        )
    }

    static let previewEmpty = SpaceModel(
        id: previewEmptyId,
        name: "Empty 3D Object",
        description: "A fixture without an imported model.",
        tags: ["Preview"],
        displayState: 0
    )

    static let previewRotated = SpaceModel(
        id: previewRotatedId,
        name: "Rotated 3D Object",
        description: "A deterministic rotated model fixture.",
        tags: ["Preview", "Rotated"],
        displayState: 0,
        degrees: 90,
        fileUrl: PreviewAssetFixture.fileUrl(
            .space,
            fileId: previewRotatedId,
            module: NetworkModules.space.token
        )
    )

    static var previewFixtures: [SpaceModel] {
        [preview, previewRotated, previewEmpty]
    }
}

extension ItemRowTreeModel {
    @MainActor
    static let preview = ItemRowTreeModel(itemId: SpaceModel.previewId, typeId: .space)
}

extension ItemController {
    @MainActor
    static var preview = SpaceRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = SpaceRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = SpaceRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = SpaceRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = SpaceRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static var preview = SpaceRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = SpaceRootModel.preview.linkController
}
