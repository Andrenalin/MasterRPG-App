// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources

public extension GeneratorRootModel {
    @MainActor
    static let preview: GeneratorRootModel = previewFixture()

    @MainActor
    static func previewFixture() -> GeneratorRootModel {
        previewFixture(models: GeneratorModel.previewFixtures)
    }

    @MainActor
    internal static func previewFixture(models: [GeneratorModel]) -> GeneratorRootModel {
        let root = GeneratorRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        return root
    }
    
    @MainActor
    static let previewWithData: GeneratorRootModel = {
        let root = GeneratorRootModel.preview
        let importController = root.importController
        let editController = root.editController
#if DEBUG
        let url = RPGResources.Resources.bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz")
        Task(priority: .userInitiated) {
            guard await PreviewFixtureLoader.importFirstExample(url: url, into: importController) else { return }
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
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        root.editController.setCurrentItem(to: .preview)
        return root
    }
#endif
}

extension GeneratorRootModel: RootExportControllable {
}

// MARK: Preview - Test
extension GeneratorModel {
    nonisolated static let previewId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x81))
    nonisolated static let previewCharacterId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x82))
    nonisolated static let previewExtractorId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x83))

    static var preview: GeneratorModel { testViewModel }

    static var previewFixtures: [GeneratorModel] {
        [testViewModel, testViewModel2, testViewModel3]
    }
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
    nonisolated static let previewId = UUID(
        uuid: (0x70, 0xE5, 0x7E, 0x66, 0x3F, 0xCE, 0x4E, 0x8E, 0xB0, 0x32, 0x5C, 0x79, 0xA2, 0x32, 0x2E, 0xB8)
    )
    nonisolated static let previewEntryId = UUID(
        uuid: (0x70, 0xE5, 0x7E, 0x66, 0x3F, 0xCE, 0x4E, 0x8E, 0xB0, 0x32, 0x5C, 0x79, 0xA2, 0x32, 0x2E, 0xB9)
    )
}

extension GeneratorModel {
    static var testViewModel: GeneratorModel {
        GeneratorModel(
            id: previewId,
            name: "Adventure Creator",
            description: "Create a playable adventure from campaign notes.",
            tags: ["AI", "Adventure"],
            displayState: 0,
            entries: [],
            genType: .adventure
        )
    }
    
    static var testViewModel2: GeneratorModel {
        GeneratorModel(
            id: previewCharacterId,
            name: "Character Generator",
            description: "Create a character with motives, traits, and game-ready details.",
            tags: ["AI", "Character"],
            displayState: 0,
            entries: [],
            genType: .character
        )
    }
    
    static var testViewModel3: GeneratorModel {
        GeneratorModel(
            id: previewExtractorId,
            name: "Extractor",
            description: "Turn unstructured notes into reusable RPG content.",
            tags: ["AI", "Extraction"],
            displayState: 0,
            entries: [],
            genType: .extractor
        )
    }
}
