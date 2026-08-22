// @copyright André Trettin

import Foundation

/// Generic replacement for the near-identical per-module `SearchController` structs — a
/// module with no search behavior beyond the shared `SearchControllable` default
/// implementations (no per-module override like CharacterRPG's group/sub-value handling)
/// needs only a one-line adoption:
/// ```swift
/// typealias SearchController = GenericSearchController<ItemController>
/// ```
/// CharacterRPG keeps its own bespoke `SearchController`, since it overrides several
/// `SearchControllable` methods with module-specific logic that a generic wrapper can't
/// express. Mirrors `GenericItemController`'s hoisting of the equivalent per-module boilerplate.
public struct GenericSearchController<IC: ItemControllable & Sendable>: Sendable {
    public init(itemController: IC) {
        self.itemController = itemController
    }

    public let itemController: IC
}

extension GenericSearchController: SearchControllable {
    public var itemControllable: any ItemControllable { itemController }
}
