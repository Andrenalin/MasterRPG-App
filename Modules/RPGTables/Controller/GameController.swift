// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGDie

public protocol TableGameStorable {
    @MainActor func addResult(_ result: ResultCategory, value: String)
    func requestTableResult(for itemId: UUID, diceId: UUID, diceResult: String, networkActions: NetworkActions?, valueActions: ValueActions) async
}

struct GameController: Sendable {
    @MainActor
    init(root: TableRootModel, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.exportController = ExportController(root: root, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(root: root, dataController: nil)
        self.importController = ImportController(root: root, itemController: internItemController, gameImporter: true)
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
    }

    weak var root: TableRootModel!
    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController

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
    var rootExportControllable: any ExportControllable {
        root.rootControllable.gameExportControllable
    }
    var rootImportControllable: any ImportControllable {
        root.rootControllable.gameImportControllable
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
        let diceNum = await root.diceRoot.diceGameControllable.number(for: diceId, result: diceResult)
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
