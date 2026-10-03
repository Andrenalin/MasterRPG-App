// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.3 — genericized in `GenericItemController` (CoreRPG); this module
/// needs no state beyond `config`/`collectionCategory`/`itemDataModel`.
typealias ItemController = GenericItemController<RuleModel>

/// The shared `GenericImportController`: this module needs no import behaviour of its own.
/// See CODE_AUDIT_Folder §9.3.
typealias ImportController = GenericImportController<ItemController, EditController>
