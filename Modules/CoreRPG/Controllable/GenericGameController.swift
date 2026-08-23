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

/// The shared core ten of twelve per-module bespoke `GameController`s
/// duplicated verbatim (`gameItem`/`setGame`/`currentItem`), because a bare
/// `typealias = GenericGameController<...>` isn't viable for a module with
/// any additional game-side behavior — see `GenericGameController`'s own
/// doc comment. A conformer supplies nothing beyond the three stored
/// properties it already has; default implementations here supply the
/// three methods, so the copies can be deleted without changing any other
/// stored property's shape or any other file's usage of them.
/// See CODE_AUDIT_Game §9.1.
@MainActor
public protocol ModuleGameControllable {
    associatedtype Item: ItemControllable & Sendable
    associatedtype Export: ExportControllable & Sendable
    var itemController: Item { get }
    var exportController: Export { get }
    var gameModel: ItemGameModel { get }
}

public extension ModuleGameControllable {
    func gameItem(for itemId: UUID) -> Item.Model {
        (gameModel.itemData[itemId] as? Item.Model) ?? itemController.itemOrEmpty(for: itemId)
    }

    func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.contains(itemId) {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }

    func currentItem() -> Item.Model {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}
