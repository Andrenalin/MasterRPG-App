// @copyright André Trettin

import AndrenalinKit
import DiceRPG
import Foundation

public protocol TableGameStorable {
    @MainActor func addResult(_ result: ResultCategory, value: String)
    func requestTableResult(for itemId: UUID, diceId: UUID, diceResult: String, networkActions: NetworkActions?, valueActions: ValueActions) async
}

struct GameController: Sendable {
    @MainActor init(diceRoot: DiceRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, rootExportControllable: any ExportControllable, rootImportControllable: any ImportControllable) {
        self.diceRoot = diceRoot
        self.itemController = itemController
        self.exportController = ExportController(diceRoot: diceRoot, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(dataController: nil, linkRegisterControllable: linkRegisterControllable)
        self.importController = ImportController(itemController: internItemController)
        self.rootExportControllable = rootExportControllable
        self.rootImportControllable = rootImportControllable
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
    }

    let diceRoot: DiceRootModel
    let itemController: ItemController
    let exportController: ExportController
    let importController: ImportController
    let rootExportControllable: any ExportControllable
    let rootImportControllable: any ImportControllable

    let gameModel: ItemGameModel

    @MainActor
    func gameItem(for itemId: UUID) -> TableModel {
        (gameModel.itemData[itemId] as? TableModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor
    func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor
    func currentItem() -> TableModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    var importControllable: any ImportControllable {
        importController as ImportControllable
    }
}

extension GameController: TableGameStorable {
    @MainActor
    public func addResult(_ result: ResultCategory, value: String) {
        guard result.module == .table else { return }
        let model = gameItem(for: result.id)
        if let childId = result.childId {
             model[childId].diceResult = value
        } else {
            model.diceResult = value
        }
    }
    
    func requestTableResult(for itemId: UUID, diceId: UUID, diceResult: String, networkActions: NetworkActions?, valueActions: ValueActions) async {
        guard let networkActions else { return }
        _ = await setCurrent(itemId: itemId)
        let diceNum = await diceRoot.diceGameControllable.number(for: diceId, result: diceResult)
        guard let entryId = await entry(for: itemId, with: diceNum) else { return }

        let model = await gameItem(for: itemId)
        let value = "\(model[entryId].content) 🎲 \(diceResult)"
        let result = await valueActions.createEntryResult(model.name, value, ResultCategory(id: itemId, childId: entryId, module: itemController.itemDataModel.networkModule))
        await networkActions.game(result, .valueResult)
    }

    @MainActor
    func entry(for id: UUID, with result: Int) -> UUID? {
        let item = gameItem(for: id)
        switch item.tableType {
        case .dice:
            if let _ = item.diceId {
                let entry = item.entries.first {
                    let numbers = $0.name.split(separator: "-").compactMap { Int($0) }
                    if let last = numbers.last {
                        return result <= last
                    }
                    return false
                }
                if let uuid = entry?.id {
                    return uuid
                }
            }
            return nil
        case .list, .all:
            let index = result - 1
            if index >= 0 && index < item.entries.count {
                return item.entries[index].id
            }
            return nil
        }
    }
}
