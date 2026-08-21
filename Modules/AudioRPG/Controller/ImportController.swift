// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.2 — genericized in `GenericImportController` (CoreRPG); this module needs
/// no behavior beyond the shared default.
typealias ImportController = GenericImportController<ItemController, EditController>
