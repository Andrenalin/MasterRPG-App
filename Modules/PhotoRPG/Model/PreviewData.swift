// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources

public extension PhotoRootModel {
    static let previewPhotoId = PhotoModel.previewId

    @MainActor
    static let preview: PhotoRootModel = {
        let root = PhotoRootModel(tagController: .preview)
        root.setUp(context: nil, rootControllable: root, linkRegisterController: LinkRegisterController(root: nil))
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: PhotoRootModel = {
        let root = PhotoRootModel.preview
        let importController = root.importController
        let editController = root.editController
#if DEBUG
        Task.detached(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try await task.value
            Task { @MainActor in
                editController.setCurrentItem(to: .previewWithData)
            }
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot() -> PhotoRootModel {
        let root = PhotoRootModel(tagController: .preview)
        root.setUp(context: nil, rootControllable: root, linkRegisterController: LinkRegisterController(root: nil))
        return root
    }
#endif
}

extension PhotoRootModel: RootControllable {
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
extension PhotoModel {
    static let previewId = UUID(uuidString: "12975503-CC29-4837-8018-EFF774E97595")!
    static let preview = PhotoModel(id: previewId, name: "ExodusAtlantisMap", description: "Imaginary map of Atlantis for Amber DRPG \"Exodus\", a tabletop roleplaying game. Author: Theresa Thomas. From Wikimedia: [Wikipedia](https://commons.wikimedia.org/wiki/File:ExodusAtlantisMap.jpg)", tags: ["Map", "Fanatasy"], degrees: 0, entries: [])
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: PhotoModel.previewId, typeId: .photo)
    @MainActor
    static var previewWithData: ItemRowTreeModel = {
        let root = PhotoRootModel.previewWithData
        return ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], entryId: nil, typeId: .photo)
    }()

}

extension ItemController {
    @MainActor
    static let preview = PhotoRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = PhotoRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = PhotoRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = PhotoRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = PhotoRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static var preview = PhotoRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = PhotoRootModel.preview.linkController
}
