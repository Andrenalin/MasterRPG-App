// @copyright André Trettin

import Foundation

/// Generic replacement for the near-identical per-module "small-tier" `GameController`
/// structs — a module with no extra game-side behavior beyond tracking the current/game
/// item set needs only a one-line adoption:
/// ```swift
/// typealias GameController = GenericGameController<ItemController, ExportController>
/// ```
/// Modules with richer game behavior still provide their own bespoke `GameController`.
/// See CODE_AUDIT §9.3.
public struct GenericGameController<
    Item: ItemControllable & Sendable,
    Export: ExportControllable & Sendable
>: Sendable {
    @MainActor public init(itemController: Item, exportController: Export) {
        self.itemController = itemController
        self.exportController = exportController
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
    }

    public let itemController: Item
    public let exportController: Export
    public let gameModel: ItemGameModel

    @MainActor public func gameItem(for itemId: UUID) -> Item.Model {
        (gameModel.itemData[itemId] as? Item.Model) ?? itemController.itemOrEmpty(for: itemId)
    }

    @MainActor public func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.contains(itemId) {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }

    @MainActor public func currentItem() -> Item.Model {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GenericGameController: GameControllable {
    public var itemControllable: any ItemControllable { itemController }
    public var exportControllable: any ExportControllable { exportController }
}
