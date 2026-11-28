// @copyright André Trettin

import CoreRPG
import Foundation

/// The shared `GenericEditController`: the never-read `selectionReference` was the only stored
/// state of its own. See CODE_AUDIT_Folder §9.2, §9.3.
/// Its only module setter, `add(referenceId:model:)`, had no production caller and mutated the
/// stored instance it was handed. See CODE_AUDIT_Edit_Save §9.7.
typealias EditController = GenericEditController<GeneratorModel>
