// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.3 — genericized in `GenericItemController` (CoreRPG); this module
/// needs no state beyond `config`/`collectionCategory`/`itemDataModel`.
typealias ItemController = GenericItemController<AdventureModel>

// The search is the module's own `SearchController`: it adds the level search.
