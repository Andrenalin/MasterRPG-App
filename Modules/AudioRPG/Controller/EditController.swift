// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT_EditItem §9.1 — genericized in `GenericEditController` (CoreRPG);
/// this module has no extra stored state beyond the generic default.
typealias EditController = GenericEditController<AudioModel>
