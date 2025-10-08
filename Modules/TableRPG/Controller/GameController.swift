// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import os.log

public protocol TableGameStorable: GameControllable {
    @MainActor func addResult(_ result: ResultCategory, value: String)
    func requestTableResult(for itemId: UUID, diceId: UUID, diceResult: String, networkActions: NetworkActions?, valueActions: ValueActions) async
}

struct GameController: Sendable {
    @MainActor
    init(itemController: ItemController, diceRoot: DiceRootModel) {
        self.itemController = itemController
        self.exportController = ExportController(module: itemController.module, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(container: itemController.container, module: itemController.module)
        self.importController = ImportController(itemController: internItemController, module: itemController.module)
        self.gameModel = ItemGameModel()
        self.diceRoot = diceRoot
    }

    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    
    let gameModel: ItemGameModel
    let diceRoot: DiceRootModel
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    @MainActor var importControllable: any ImportControllable {
        importController as ImportControllable
    }
}

extension GameController: TableGameStorable {
    @MainActor
    public func addResult(_ result: ResultCategory, value: String) {
        guard result.module == .table else { return }
        let model = gameItem(for: result.id)
//        if let childId = result.childId {
//             model[childId].diceResult = value
//        } else {
//            model.diceResult = value
//        }
    }
    
    func requestTableResult(for itemId: UUID, diceId: UUID, diceResult: String, networkActions: NetworkActions?, valueActions: ValueActions) async {
        guard let networkActions else { return }
        _ = await setCurrent(itemId: itemId)
        //let diceNum = await diceRoot.gameControllable.number(for: diceId, result: diceResult)
        let diceNum = 1
        guard let entryId = await entry(for: itemId, with: diceNum) else { return }

        guard let model = await gameItem(for: itemId) else { return }
        let value = "" // \(model[entryId].content) 🎲 \(diceResult)"
        let result = await valueActions.createEntryResult(model.name.wrappedValue, value, ResultCategory(id: itemId, childId: entryId, module: itemController.module))
        await networkActions.game(result, .valueResult)
    }

    @MainActor
    func entry(for id: UUID, with result: Int) -> UUID? {
        guard let item = gameItem(for: id) else { return nil }
        return nil
//        switch item.tableType {
//        case .dice:
//            if let _ = item.diceId {
//                let entry = item.entries.first {
//                    let numbers = $0.name.split(separator: "-").compactMap { Int($0) }
//                    if let last = numbers.last {
//                        return result <= last
//                    }
//                    return false
//                }
//                if let uuid = entry?.id {
//                    return uuid
//                }
//            }
//            return nil
//        case .list, .all:
//            let index = result - 1
//            if index >= 0 && index < item.entries.count {
//                return item.entries[index].id
//            }
//            return nil
//        }
    }
}
