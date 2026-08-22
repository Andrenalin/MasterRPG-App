// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

/// See CODE_AUDIT_EditItem §9.1 — genericized in `GenericEditController` (CoreRPG);
/// this module has no extra stored state beyond the generic default.
typealias EditController = GenericEditController<SpaceModel>
