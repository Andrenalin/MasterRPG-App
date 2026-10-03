// @copyright André Trettin

import Foundation

public struct ReviewSheetMemory: Sendable {
    public init(
        items: [NetworkModules: [UUID: any ItemDataAccessible]],
        hiddenItemIds: [NetworkModules: Set<UUID>] = [:]
    ) {
        self.resolve = { itemId, module in
            if hiddenItemIds[module]?.contains(itemId) == true { return .hidden }
            return items[module]?[itemId].map(Lookup.item) ?? .notInReview
        }
    }

    /// A memory that builds each review item when the sheet first reads it, and keeps it for
    /// later reads. Building every item of the review up front copied the whole batch, which
    /// for a subset import includes every other local item, on each decision change.
    /// See CODE_AUDIT_Folder §7.3.
    @MainActor init(lookup: @escaping @MainActor @Sendable (UUID, NetworkModules) -> Lookup) {
        let cache = LookupCache()
        self.resolve = { itemId, module in
            cache.value(for: itemId, module: module, lookup: lookup)
        }
    }

    enum Lookup {
        case item(any ItemDataAccessible)
        case hidden
        case notInReview
    }

    private let resolve: @MainActor @Sendable (UUID, NetworkModules) -> Lookup

    @MainActor public func item(for itemId: UUID, module: NetworkModules) -> (any ItemDataAccessible)? {
        if case .item(let item) = resolve(itemId, module) { return item }
        return nil
    }

    @MainActor public func hides(itemId: UUID, module: NetworkModules) -> Bool {
        if case .hidden = resolve(itemId, module) { return true }
        return false
    }
}

@MainActor
private final class LookupCache: Sendable {
    private struct Key: Hashable {
        let itemId: UUID
        let module: NetworkModules
    }

    private var values: [Key: ReviewSheetMemory.Lookup] = [:]

    func value(
        for itemId: UUID,
        module: NetworkModules,
        lookup: @MainActor (UUID, NetworkModules) -> ReviewSheetMemory.Lookup
    ) -> ReviewSheetMemory.Lookup {
        let key = Key(itemId: itemId, module: module)
        if let value = values[key] { return value }
        let value = lookup(itemId, module)
        values[key] = value
        return value
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
