// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources

public extension AudioRootModel {
    @MainActor
    static let preview: AudioRootModel = {
        let root = AudioRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, linkRegisterController: LinkRegisterController(root: realRootManager))
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
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
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

@MainActor
extension AudioRootModel: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
    public var gameExportControllable: any ExportControllable {
        exportController
    }
    public var gameImportControllable: any ImportControllable {
        importController
    }
}

// MARK: Preview - Test
extension AudioModel {
    nonisolated static let previewId = UUID()
    @MainActor static let preview = AudioModel.empty(AudioModel.previewId)
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
