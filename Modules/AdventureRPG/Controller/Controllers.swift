// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.3 — genericized in `GenericItemController` (CoreRPG); this module
/// needs no state beyond `config`/`collectionCategory`/`itemDataModel`.
typealias ItemController = GenericItemController<AdventureModel>

/// The shared search of `GenericSearchController` (CoreRPG); this module adds nothing to it.
typealias SearchController = GenericSearchController<ItemController>
