// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.3 — genericized in `GenericGameController` (CoreRPG); this module
/// needs no game behavior beyond tracking the current/game item set.
typealias GameController = GenericGameController<ItemController, ExportController>
