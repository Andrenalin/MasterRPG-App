// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources

public extension DiceRootModel {
    static let previewDiceId = DiceModel.previewId
    
    @MainActor
    static let preview: DiceRootModel = previewFixture()

    @MainActor
    internal static func previewFixture(
        models: [DiceModel] = DiceModel.previewFixtures,
        focusedId: UUID? = DiceModel.previewId
    ) -> DiceRootModel {
        let root = DiceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.itemController.diceBag.dice = DieModel.previewBagDice
        root.editController.setCurrentItem(to: .preview)
        if let focusedId, let focusedModel = models.first(where: { $0.id == focusedId }) {
            root.gameController.setGame(item: focusedModel.copy(), itemId: focusedId)
            root.gameController.gameModel.focusItemIds = [focusedId]
        }
        return root
    }

    @MainActor
    static func preview(id: UUID) -> DiceRootModel {
        previewFixture(focusedId: id)
    }
    
    @MainActor
    static let previewWithData: DiceRootModel = {
        let root = DiceRootModel.preview
        let importController = root.importController
        let editController = root.editController
        let gameController = root.gameController
        let itemController = root.itemController
#if DEBUG
        let url = RPGResources.Resources.bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz")
        Task(priority: .userInitiated) {
            guard await PreviewFixtureLoader.importFirstExample(url: url, into: importController) else { return }
            let saveTask = Task { @MainActor in
                editController.setCurrentItem(to: .previewWithData)
                await gameController.setFocusDice(on: itemController.itemDataModel.items[0])
            }
            _ = await saveTask.result
            _ = await gameController.setCurrent(itemId: itemController.itemDataModel.items[0])
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot() -> DiceRootModel {
        let root = DiceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

@MainActor
extension DiceRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: DiceModel.previewId, typeId: .dice)
    static func preview(id: UUID) -> ItemRowTreeModel {
        ItemRowTreeModel(itemId: id, typeId: .dice)
    }
    @MainActor
    static var previewWithData: ItemRowTreeModel = {
        let root = DiceRootModel.previewWithData
        return ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], entryId: nil, typeId: .dice)
    }()
}

extension ItemController {
    @MainActor
    static let preview = DiceRootModel.preview.itemController
    
    @MainActor
    static func setPreviewData(for controller: ItemController) async {
        for model in DiceModel.previewFixtures {
            controller.replace(model: model, isInsert: true)
        }
    }
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = DiceRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = DiceRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = DiceRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = DiceRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static var preview = DiceRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = DiceRootModel.preview.linkController
}

// MARK: Preview - Test
extension DiceModel {
    nonisolated static let previewId = UUID(uuid: (0x22, 0x01, 0xFB, 0xB7, 0x04, 0x03, 0x4A, 0x18, 0xA3, 0x61, 0xCA, 0xD5, 0xA7, 0x6A, 0x63, 0x7D))
    // nonisolated: consumed by the (nonisolated) widget configuration default.
    nonisolated static public let preview = previewSnapshot.makeModel()
    nonisolated static public let previewSnapshot = DiceSnapshot(
        id: previewId,
        name: "DS",
        description: "Here is a DungeonSlayer Dice. With Fumble of 20, Coup of 1 and exploding dice on 1. Every 20 values is 1 die. So values over 20 are 2d20.  Values over 40 are 3d20 and so on. On success the order of dice are highest to lowest.",
        tags: ["DS", "Example"],
        category: .game,
        displayState: 0,
        dice: [
            DieModel(
                id: UUID(uuid: (0x87, 0xC7, 0xE2, 0x92, 0xDE, 0xFA, 0x45, 0x6B, 0xB0, 0x09, 0x34, 0x1E, 0xDE, 0x85, 0x96, 0x89)),
                die: RawDie.twenty,
                color: DieModel.ColorCode.G.rawValue,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
        ],
        sumUp: true,
        modifier: 0.0,
        percentDice: false,
        compareOption: .lowerEqual,
        compareValue: 14.0,
        coupValues: [.diceValue(1)],
        coupOnlyOnFirstDie: true,
        fumbleValues: [.diceValue(20)],
        fumbleOnlyOnFirstDie: true,
        rerollOptions: [RerollOption(number: 1, value: 0, maxDiceValue: true)],
        reorderDice: true,
        addDiceEvery: 20,
        resultCategory: nil
    )
    
    static let uuidCoC = UUID(uuid: (0x44, 0x01, 0xFB, 0xB7, 0x04, 0x03, 0x4A, 0x18, 0xA3, 0x61, 0xCA, 0xD5, 0xA7, 0x6A, 0x63, 0x7D))
    static let diceCoC: DiceModel = .init(
        id: uuidCoC,
        name: "CoC",
        description: "This is a dice for Call of Cthuhlu. A percent five where you need to roll equal or lower the value. 01 is a critical and 05 is extreme success. 100 is a fumble.",
        tags: ["CoC", "Example"],
        category: .game,
        displayState: 0,
        dice: [
            DieModel(
                id: UUID(uuid: (0x81, 0x5B, 0xFF, 0x42, 0x1D, 0xB4, 0x4F, 0x6D, 0x96, 0x12, 0xAA, 0x52, 0xA4, 0xB3, 0xE2, 0x00)),
                die: RawDie.ten,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
            DieModel(
                id: UUID(uuid: (0x4C, 0xC8, 0x9B, 0xC8, 0x12, 0x90, 0x41, 0xAE, 0x9F, 0xAE, 0xE9, 0x8E, 0xA5, 0xD0, 0xF3, 0x4C)),
                die: RawDie.ten,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
        ],
        sumUp: true,
        modifier: 0.0,
        percentDice: true,
        compareOption: .lowerEqual,
        compareValue: 65.0,
        coupValues: [.result(1), .result(5)],
        coupOnlyOnFirstDie: false,
        fumbleValues: [.result(100)],
        fumbleOnlyOnFirstDie: false,
        rerollOptions: [],
        reorderDice: false,
        addDiceEvery: 0,
        resultCategory: nil
    )
    
    static let uuidERPS = UUID(uuid: (0x98, 0x56, 0xEA, 0x10, 0xFC, 0x63, 0x44, 0x6F, 0x9F, 0x90, 0xF4, 0x09, 0x7B, 0x8F, 0x7A, 0x15))
    static let diceERPS: DiceModel = .init(
        id: uuidERPS,
        name: "ERPS",
        description: "ERPS uses 2d10 and sum up the values. 10 is a re-roll and count as 10. Fumble is 2 with 2d10.",
        tags: ["ERPS", "Example"],
        category: .game,
        displayState: 0,
        dice: [
            DieModel(
                id: UUID(uuid: (0xCA, 0xE4, 0xEF, 0xCB, 0xD0, 0x79, 0x42, 0x49, 0x83, 0x78, 0xB0, 0x1E, 0x09, 0x53, 0x68, 0x6B)),
                die: RawDie.ten,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
            DieModel(
                id: UUID(uuid: (0x1E, 0xA3, 0x96, 0xF4, 0x8B, 0x11, 0x4B, 0x29, 0x9F, 0x22, 0x0B, 0x3E, 0xA2, 0x9C, 0x35, 0xAC)),
                die: RawDie.ten,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
        ],
        sumUp: true,
        modifier: 0.0,
        percentDice: false,
        compareOption: .equalHigher,
        compareValue: 14.0,
        coupValues: [],
        coupOnlyOnFirstDie: false,
        fumbleValues: [.result(2)],
        fumbleOnlyOnFirstDie: false,
        rerollOptions: [RerollOption(number: 10, value: 10, maxDiceValue: false)],
        reorderDice: false,
        addDiceEvery: 0,
        resultCategory: nil
    )
    
    @MainActor
    static var previewFixtures: [DiceModel] {
        [previewSnapshot.makeModel(), diceCoC.copy(), diceERPS.copy()]
    }

    @MainActor
    static var diceList: [DiceModel] {
        previewFixtures
    }
}

extension DieModel {
    nonisolated static let previewDisplayTen = DieModel(
        id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
        die: .ten,
        color: ColorCode.G.rawValue
    )

    nonisolated static let previewDisplayTwenty = DieModel(
        id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
        die: .twenty,
        color: ColorCode.A.rawValue
    )

    nonisolated static let previewDisplaySuccess = DieModel(
        id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
        die: .twenty,
        color: ColorCode.G.rawValue,
        result: [20, 1]
    )

    nonisolated static let previewDisplayFailure = DieModel(
        id: UUID(uuid: (0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4)),
        die: .twenty,
        color: ColorCode.G.rawValue,
        result: [7, 20]
    )

    nonisolated static let previewBagDice: [DieModel] = [
        DieModel(
            id: UUID(uuid: (0xD2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            die: .four,
            color: ColorCode.G.rawValue
        ),
        DieModel(
            id: UUID(uuid: (0xD2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
            die: .six,
            color: ColorCode.G.rawValue
        ),
        DieModel(
            id: UUID(uuid: (0xD2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
            die: .eight,
            color: ColorCode.G.rawValue
        ),
        DieModel(
            id: UUID(uuid: (0xD2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4)),
            die: .ten,
            color: ColorCode.G.rawValue
        ),
        DieModel(
            id: UUID(uuid: (0xD2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5)),
            die: .twelve,
            color: ColorCode.G.rawValue
        ),
        DieModel(
            id: UUID(uuid: (0xD2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6)),
            die: .twenty,
            color: ColorCode.G.rawValue
        )
    ]
}
