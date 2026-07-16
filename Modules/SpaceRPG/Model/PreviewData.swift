// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources

public extension SpaceRootModel {
    static let previewSpaceId = SpaceModel.previewId
    
    @MainActor
    static let preview: SpaceRootModel = {
        let root = SpaceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: SpaceRootModel = {
        let root = SpaceRootModel.preview
        let importController = root.importController
#if DEBUG
        Task(priority: .userInitiated) {
            let bundle = RPGResources.Resources.bundle
            guard let url = bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url, withOverwrite: true)
            let _ = try? await task.value
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot() -> SpaceRootModel {
        let root = SpaceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
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

    static let preview = SpaceModel(id: previewId, name: "ExodusAtlantisMap", description: "Imaginary map of Atlantis for Amber DRPG \"Exodus\", a tabletop roleplaying game. Author: Theresa Thomas. From Wikimedia: [Wikipedia](https://commons.wikimedia.org/wiki/File:ExodusAtlantisMap.jpg)", tags: ["Map", "Fanatasy"], displayState: 0, degrees: 0, entries: [])

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
        degrees: 90
    )
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

private extension UUID {
    nonisolated static func fixture(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid deterministic preview UUID: \(value)")
        }
        return id
    }
}
