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
    static let preview: CharacterRootModel = previewFixture()

    @MainActor
    internal static func previewFixture(
        models: [ValueModel] = ValueModel.previewFixtures
    ) -> CharacterRootModel {
        let root = CharacterRootModel(tagController: .preview, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.tableRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        return root
    }
    
    @MainActor
    static let previewWithData: CharacterRootModel = {
        let root = CharacterRootModel.preview
        let importController = root.importController
#if DEBUG
        Task(priority: .userInitiated) {
            let bundle = RPGResources.Resources.bundle
            guard let url = bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try? await task.value
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        let root = CharacterRootModel(tagController: .preview, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.tableRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        return root
    }
#endif
}

@MainActor
extension CharacterRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
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
    nonisolated static let previewId = UUID(uuid: (0x15, 0x27, 0x14, 0x0F, 0x01, 0x01, 0x46, 0xC3, 0x91, 0x2E, 0xB0, 0x2F, 0xE0, 0xFF, 0x76, 0x96))
    nonisolated static let previewAllEntryTypesId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x32))
    nonisolated static let previewEmptyId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x33))

    @MainActor
    static let preview = ValueModel(id: previewId, name: "Andrenalin", description: "GameMaster forever", tags: ["Master", "Guide", "Coder"], category: .gameMaster, displayState: 0, photoId: PhotoRootModel.previewPhotoId, photos: [], entries: [.testEntryText, .testEntryNumber])

    @MainActor
    static let previewAllEntryTypes = ValueModel(
        id: previewAllEntryTypesId,
        name: "Mira the Cartographer",
        description: "Fixture containing every value-entry presentation.",
        tags: ["Player", "Explorer"],
        entries: [.testEntryText, .testEntryNumber, .testEntryDecimal, .testEntrySelection]
    )

    @MainActor
    static let previewEmpty = ValueModel(id: previewEmptyId, name: "Empty Character")

    @MainActor
    static var previewFixtures: [ValueModel] {
        [
            ValueModel(
                id: previewId,
                name: "Andrenalin",
                description: "GameMaster forever",
                tags: ["Master", "Guide", "Coder"],
                category: .gameMaster,
                photoId: PhotoRootModel.previewPhotoId,
                entries: [.testEntryText, .testEntryNumber]
            ),
            ValueModel(
                id: previewAllEntryTypesId,
                name: "Mira the Cartographer",
                description: "Fixture containing every value-entry presentation.",
                tags: ["Player", "Explorer"],
                entries: [.testEntryText, .testEntryNumber, .testEntryDecimal, .testEntrySelection]
            ),
            ValueModel(id: previewEmptyId, name: "Empty Character")
        ]
    }
}

extension ValueEntryModel {
    nonisolated static let previewId = UUID(uuid: (0x5B, 0xD8, 0xF0, 0xAF, 0x7B, 0x6D, 0x42, 0x81, 0x89, 0x4F, 0xC0, 0x8B, 0x53, 0xE5, 0xD1, 0xB2))

    static var testEntryText: ValueEntryModel {
        ValueEntryModel(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x34)),
            name: "Character name",
            type: .text,
            value: "Andrenalin"
        )
    }

    static var testEntryNumber: ValueEntryModel {
        ValueEntryModel(id: previewId, name: "Unverwundbartrank", type: .number, value: "1000")
    }

    static var testEntryDecimal: ValueEntryModel {
        ValueEntryModel(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x35)),
            name: "Movement",
            type: .decimal,
            value: "0|7.5"
        )
    }

    static var testEntrySelection: ValueEntryModel {
        ValueEntryModel(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x36)),
            name: "Inspired",
            type: .selection,
            value: "I"
        )
    }
}
