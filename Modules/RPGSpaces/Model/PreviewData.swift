// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData
import RPGResources

public extension SpaceRoot {
    static let previewSpaceId = SpaceModel.previewId
    
    @MainActor
    static let preview: SpaceRoot = {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = SpaceRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        root.editController(type: .main).setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: SpaceRoot = {
        let root = SpaceRoot.preview
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
    static func testRoot() -> SpaceRoot {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = SpaceRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        return root
    }
#endif

    @MainActor static let linkRegisterController = FakeLinkRegisterController()
}

extension SpaceRoot: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    public var linkRegisterControllable: LinkRegisterControllable {
        SpaceRoot.linkRegisterController
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
    static let preview = SpaceModel(id: previewId, name: "ExodusAtlantisMap", description: "Imaginary map of Atlantis for Amber DRPG \"Exodus\", a tabletop roleplaying game. Author: Theresa Thomas. From Wikimedia: [Wikipedia](https://commons.wikimedia.org/wiki/File:ExodusAtlantisMap.jpg)", tags: ["Map", "Fanatasy"], degrees: 0, entries: [])
}

extension ItemRowTreeModel {
    @MainActor
    static let preview = ItemRowTreeModel(itemId: SpaceModel.previewId, typeId: .space)
}

extension ItemController {
    @MainActor
    static var preview = SpaceRoot.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = SpaceRoot.preview.editController(type: .main)
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = SpaceRoot.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = SpaceRoot.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = SpaceRoot.preview.exportController
}

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static var preview = SpaceRoot.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static var preview = SpaceRoot.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = SpaceRoot.preview.linkController
}
