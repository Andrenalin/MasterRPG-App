// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.3 — genericized in `GenericItemController` (CoreRPG); this module
/// needs no state beyond `config`/`collectionCategory`/`itemDataModel`.
typealias ItemController = GenericItemController<GeneratorModel>

/// See CODE_AUDIT §9.2 — genericized in `GenericImportController` (CoreRPG); this module needs
/// no behavior beyond the shared default.
typealias ImportController = GenericImportController<ItemController, EditController>

/// The shared search of `GenericSearchController` (CoreRPG); this module adds nothing to it.
typealias SearchController = GenericSearchController<ItemController>

/// See CODE_AUDIT §9.2 — genericized in `GenericExportController` (CoreRPG); this module has no
/// per-item companion assets beyond its own item tree, so it needs no behavior beyond the shared
/// default.
typealias ExportController = GenericExportController<ItemController>

/// See CODE_AUDIT §9.3 — genericized in `GenericGameController` (CoreRPG); this module
/// needs no game behavior beyond tracking the current/game item set.
typealias GameController = GenericGameController<ItemController, ExportController>
