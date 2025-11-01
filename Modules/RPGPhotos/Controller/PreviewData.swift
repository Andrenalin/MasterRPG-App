// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData
import RPGResources

public extension PhotoRoot {
    static let previewPhotoId = PhotoModel.previewId

    @MainActor
    static let preview: PhotoRoot = {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = PhotoRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        root.editController(type: .main).setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: PhotoRoot = {
        let root = PhotoRoot.preview
        let importController = root.importController
        let editController = root.editController(type: .main)
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
    static func testRoot() -> PhotoRoot {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = PhotoRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        return root
    }
#endif

    @MainActor
    static let linkRegisterController = FakeLinkRegisterController()
}

extension PhotoRoot: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    @MainActor
    public var linkRegisterControllable: LinkRegisterControllable {
        PhotoRoot.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        gameController.exportController
    }
    public var gameImportControllable: any ImportControllable {
        gameController.importController
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
        let root = PhotoRoot.previewWithData
        return ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], entryId: nil, typeId: .photo)
    }()

}

extension ItemController {
    @MainActor
    static let preview = PhotoRoot.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = PhotoRoot.preview.editController(type: .main)
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = PhotoRoot.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = PhotoRoot.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = PhotoRoot.preview.exportController
}

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static var preview = PhotoRoot.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static var preview = PhotoRoot.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = PhotoRoot.preview.linkController
}
