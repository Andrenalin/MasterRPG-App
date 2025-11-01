// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData
import RPGResources

public extension AudioRoot {
    @MainActor
    static let preview: AudioRoot = {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = AudioRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        root.editController(type: .main).setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: AudioRoot = {
        let root = AudioRoot.preview
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
    static func testRoot() -> AudioRoot {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = AudioRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        return root
    }
#endif

    @MainActor
    static let linkRegisterController = FakeLinkRegisterController()
}

extension AudioRoot: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
    
    @MainActor
    public var linkRegisterControllable: LinkRegisterControllable {
        AudioRoot.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        gameController.exportController
    }
    public var gameImportControllable: any ImportControllable {
        gameController.importController
    }
}

// MARK: Preview - Test
extension AudioModel {
    static let previewId = UUID()
    static let preview = AudioModel.empty(AudioModel.previewId)
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: AudioModel.previewId, typeId: .audio)
    @MainActor
    static var previewWithData: ItemRowTreeModel = {
        let root = AudioRoot.previewWithData
        return ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .audio)
    }()
}

extension ItemController {
    @MainActor
    static var preview = AudioRoot.preview.itemController
    }

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = AudioRoot.preview.editController(type: .main)
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = AudioRoot.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = AudioRoot.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = AudioRoot.preview.exportController
}

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static var preview = AudioRoot.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static var preview = AudioRoot.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = AudioRoot.preview.linkController
}
