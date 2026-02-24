// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources

public extension DiceRootModel {
    static let previewDiceId = DiceModel.previewId
    
    @MainActor
    static let preview: DiceRootModel = {
        let root = DiceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, linkRegisterController: LinkRegisterController(root: realRootManager))
        root.itemController.replace(model: DiceModel.preview, isInsert: true)
        root.editController.setCurrentItem(to: .preview)

        Task {
            await _ = root.gameController.setCurrent(itemId: DiceModel.previewId)
        }
        return root
    }()
    
    @MainActor
    static func preview(id: UUID) -> DiceRootModel {
        let root = DiceRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        root.itemController.replace(model: DiceModel.preview, isInsert: true)
        root.editController.setCurrentItem(to: .preview)
        Task {
            _ = await root.gameController.setCurrent(itemId: id)
        }
        return root
    }
    
    @MainActor
    static let previewWithData: DiceRootModel = {
        let root = DiceRootModel.preview
        let importController = root.importController
        let editController = root.editController
        let gameController = root.gameController
        let itemController = root.itemController
#if DEBUG
        Task.detached(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try await task.value
            let saveTask = Task { @MainActor in
                editController.setCurrentItem(to: .previewWithData)
                gameController.setFocusDice(on: itemController.itemDataModel.items[0])
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
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

@MainActor
extension DiceRootModel: RootControllable {
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
        controller.replace(model: DiceModel.preview, isInsert: false)
        controller.replace(model: DiceModel.diceERPS, isInsert: false)
        controller.replace(model: DiceModel.diceCoC, isInsert: false)
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
    static let previewId = UUID(uuidString: "2201FBB7-0403-4A18-A361-CAD5A76A637D")!
    static let preview = DiceModel(
        id: previewId,
        name: "DS",
        description: "Here is a DungeonSlayer Dice. With Fumble of 20, Coup of 1 and exploding dice on 1. Every 20 values is 1 die. So values over 20 are 2d20.  Values over 40 are 3d20 and so on. On success the order of dice are highest to lowest.",
        tags: ["DS", "Example"],
        category: .game,
        displayState: 0,
        dice: [
            DieModel(
                id: UUID(uuidString: "87C7E292-DEFA-456B-B009-341EDE859689")!,
                die: RawDie.twenty,
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
        reroleOptions: [RerollOption(number: 1, value: 0, maxDiceValue: true)],
        reorderDice: true,
        addDiceEvery: 20,
        resultCategory: nil
    )
    
    static let uuidCoC = UUID(uuidString: "4401FBB7-0403-4A18-A361-CAD5A76A637D")!
    static let diceCoC: DiceModel = .init(
        id: uuidCoC,
        name: "CoC",
        description: "This is a dice for Call of Cthuhlu. A percent five where you need to role equal or lower the value. 01 is a critical and 05 is extreme success. 100 is a fumble.",
        tags: ["CoC", "Example"],
        category: .game,
        displayState: 0,
        dice: [
            DieModel(
                id: UUID(uuidString: "815BFF42-1DB4-4F6D-9612-AA52A4B3E200")!,
                die: RawDie.ten,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
            DieModel(
                id: UUID(uuidString: "4CC89BC8-1290-41AE-9FAE-E98EA5D0F34C")!,
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
        reroleOptions: [],
        reorderDice: false,
        addDiceEvery: 0,
        resultCategory: nil
    )
    
    static let uuidERPS = UUID(uuidString: "9856EA10-FC63-446F-9F90-F4097B8F7A15")!
    static let diceERPS: DiceModel = .init(
        id: uuidERPS,
        name: "ERPS",
        description: "ERPS uses 2d10 and sum up the values. 10 is a re-role and count as 10. Fumble is 2 with 2d10.",
        tags: ["ERPS", "Example"],
        category: .game,
        displayState: 0,
        dice: [
            DieModel(
                id: UUID(uuidString: "CAE4EFCB-D079-4249-8378-B01E0953686B")!,
                die: RawDie.ten,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
            DieModel(
                id: UUID(uuidString: "1EA396F4-8B11-4B29-9F22-0B3EA29C35AC")!,
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
        reroleOptions: [RerollOption(number: 10, value: 10, maxDiceValue: false)],
        reorderDice: false,
        addDiceEvery: 0,
        resultCategory: nil
    )
    
    static var diceList: [DiceModel] {
        [diceCoC, preview, diceERPS]
    }
}
