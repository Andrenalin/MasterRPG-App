// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.2 — genericized in `GenericExportController` (CoreRPG); this module has no
/// per-item companion assets beyond its own item tree, so it needs no behavior beyond the shared
/// default.
typealias ExportController = GenericExportController<ItemController>
