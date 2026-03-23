// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import PhotoRPG
import RPGResources
import TableRPG

public extension CharacterRootModel {
    static let previewValueId = ValueModel.previewId

    @MainActor
    static let preview: CharacterRootModel = {
        let root = CharacterRootModel(tagController: .preview, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.tableRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.itemController.replace(model: ValueModel.preview, isInsert: true)
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: CharacterRootModel = {
        let root = CharacterRootModel.preview
        let importController = root.importController
#if DEBUG
        Task(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try await task.value
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        let root = CharacterRootModel(tagController: .preview, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.tableRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        return root
    }
#endif
}

@MainActor
extension CharacterRootModel: RootControllable {
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

extension ItemRowTreeModel {
    @MainActor
    static let preview = ItemRowTreeModel(itemId: ValueModel.previewId, entryId: ValueEntryModel.previewId, typeId: .value)
}

extension ItemController {
    @MainActor
    static let preview = CharacterRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = CharacterRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static let preview = CharacterRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static let preview = CharacterRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static let preview = CharacterRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static let preview = CharacterRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static let preview = CharacterRootModel.preview.linkController
}

extension ValueModel {
    static let previewId = UUID(uuidString: "1527140F-0101-46C3-912E-B02FE0FF7696")!
    @MainActor
    static let preview = ValueModel(id: previewId, name: "Andrenalin", description: "GameMaster forever", tags: ["Master", "Guide", "Coder"], category: .gameMaster, displayState: 0, photoId: PhotoRootModel.previewPhotoId, photos: [], entries: [.testEntryText, .testEntryNumber])
}

extension ValueEntryModel {
    static var previewId: UUID {
        UUID(uuidString: "5BD8F0AF-7B6D-4281-894F-C08B53E5D1B2") ?? UUID()
    }

    static var testEntryText: ValueEntryModel {
        ValueEntryModel(id: UUID(), name: "Character name", type: .text, value: "Andrenalin")
    }

    static var testEntryNumber: ValueEntryModel {
        ValueEntryModel(id: previewId, name: "Unverwundbartrank", type: .number, value: "1000")
    }
}
