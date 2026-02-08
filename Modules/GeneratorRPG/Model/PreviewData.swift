// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources
import SwiftData

public extension GeneratorRootModel {
    @MainActor
    static let preview: GeneratorRootModel = {
        let root = GeneratorRootModel(tagController: .preview)
        root.setUp(context: nil, rootManager: RootManager.preview(fake: root.rootController), linkRegisterController: LinkRegisterController(root: nil))
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: GeneratorRootModel = {
        let root = GeneratorRootModel.preview
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
    static func testRoot() -> GeneratorRootModel {
        let root = GeneratorRootModel(tagController: .preview)
        root.editController.setCurrentItem(to: .preview)
        return root
    }
#endif
}

extension GeneratorRootModel: @preconcurrency RootControllable {
    public var gameExportControllable: any ExportControllable {
        exportController
    }
    public var gameImportControllable: any ImportControllable {
        importController
    }
}

// MARK: Preview - Test
extension GeneratorModel {
    static let previewId = UUID(uuidString: "5F6D6D52-3DDB-4B20-8D45-DFB543799417")!
    static let preview = testViewModel
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: GeneratorModel.previewId, typeId: .generator)
    @MainActor
    static var previewWithData: ItemRowTreeModel = {
        let root = GeneratorRootModel.previewWithData
        return ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], entryId: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]).entries[0].id, typeId: .map)
    }()
}

extension ItemController {
    @MainActor
    static let preview = GeneratorRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = GeneratorRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static let preview = GeneratorRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static let preview = GeneratorRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static let preview = GeneratorRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static let preview = GeneratorRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static let preview = GeneratorRootModel.preview.linkController
}

extension UUID {
    static let previewId = UUID(uuidString: "70E57E66-3FCE-4E8E-B032-5C79A2322EB8")!
    static let previewEntryId = UUID(uuidString: "70E57E66-3FCE-4E8E-B032-5C79A2322EB8")!
}

extension GeneratorModel {
    
    static let uuid = UUID(uuidString: "5F6D6D52-3DDB-4B20-8D45-DFB543799417")!
    static let entryUuid = UUID()
    static let testViewModel = GeneratorModel(
        id: uuid,
        name: "Adventure Creator",
        description: "Create an adventure",
        tags: ["DS"],
        displayState: 0, entries: [], genType: .adventure
    )
    
    static let uuid2 = UUID(uuidString: "8C94288B-4CDB-4109-B0AD-75B12530ED84")!
    static let testViewModel2 = GeneratorModel(
        id: uuid2,
        name: "Character Generator",
        description: "Create an Character",
        tags: ["DS", "Character"],
        displayState: 0, entries: [], genType: .character
    )
    
    static let uuid3 = UUID()
    static let testViewModel3 = GeneratorModel(id: uuid3, name: "Extractor", description: "Uses Text to build", displayState: 0, entries: [], genType: .extractor)
}

