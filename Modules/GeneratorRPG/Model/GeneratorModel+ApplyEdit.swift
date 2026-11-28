// @copyright André Trettin

import CoreRPG
import Foundation

extension GeneratorModel {
    /// Undo and redo revert the generator's own properties too. See CODE_AUDIT_Edit_Save §5.2.
    public func applyModuleUndo(from base: GeneratorModel, to edited: GeneratorModel) {
        if base.genType != edited.genType { genType = edited.genType }
        if base.referenceId != edited.referenceId { referenceId = edited.referenceId }
    }
}
