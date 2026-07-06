// @copyright André Trettin

import Foundation

public struct ReviewSheetMemory: Sendable {
    public init(
        items: [NetworkModules: [UUID: any ItemDataAccessable]],
        hiddenItemIds: [NetworkModules: Set<UUID>] = [:]
    ) {
        self.items = items
        self.hiddenItemIds = hiddenItemIds
    }

    private let items: [NetworkModules: [UUID: any ItemDataAccessable]]
    private let hiddenItemIds: [NetworkModules: Set<UUID>]

    @MainActor public func item(for itemId: UUID, module: NetworkModules) -> (any ItemDataAccessable)? {
        items[module]?[itemId]
    }

    @MainActor public func hides(itemId: UUID, module: NetworkModules) -> Bool {
        hiddenItemIds[module]?.contains(itemId) == true
    }
}

public extension ItemControllable {
    @MainActor func reviewAwareItemSync(root: RootManager, for itemId: UUID, noGame: Bool = false) -> Model? {
        guard let reviewSheetMemory = root.reviewSheetMemory else {
            return itemSync(for: itemId, noGame: noGame)
        }

        if reviewSheetMemory.hides(itemId: itemId, module: config.module) {
            return nil
        }

        if let reviewItem = reviewSheetMemory.item(for: itemId, module: config.module) as? Model {
            return reviewItem
        }

        return itemSync(for: itemId, noGame: noGame)
    }

    @MainActor func reviewAwareItemOrEmpty(root: RootManager, for itemId: UUID) -> Model {
        reviewAwareItemSync(root: root, for: itemId) ?? Model.empty(itemId)
    }
}
