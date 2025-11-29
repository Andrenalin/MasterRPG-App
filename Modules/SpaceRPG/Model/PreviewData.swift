// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import RPGResources

public extension SpaceRootModel {
    static let previewSpaceId = SpaceModel.previewId
    
    @MainActor
    static let preview: SpaceRootModel = {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = SpaceRootModel(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: SpaceRootModel = {
        let root = SpaceRootModel.preview
        let importController = root.importController
#if DEBUG
        Task.detached(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url, withOverwrite: true)
            let _ = try await task.value
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot() -> SpaceRootModel {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = SpaceRootModel(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        return root
    }
#endif

    @MainActor static let linkRegisterController = FakeLinkRegisterController()
}

extension SpaceRootModel: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    public var linkRegisterControllable: LinkRegisterControllable {
        SpaceRootModel.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        exportController
    }
    public var gameImportControllable: any ImportControllable {
        importController
    }
}

// MARK: Preview - Test
extension SpaceModel {
    static let previewId = UUID(uuidString: "F5AC90DF-36F2-4151-B283-F0CF9D0BAC35")!
    static let preview = SpaceModel(id: previewId, name: "ExodusAtlantisMap", description: "Imaginary map of Atlantis for Amber DRPG \"Exodus\", a tabletop roleplaying game. Author: Theresa Thomas. From Wikimedia: [Wikipedia](https://commons.wikimedia.org/wiki/File:ExodusAtlantisMap.jpg)", tags: ["Map", "Fanatasy"], displayState: 0, degrees: 0, entries: [])
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

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static var preview = SpaceRootModel.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static var preview = SpaceRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = SpaceRootModel.preview.linkController
}
