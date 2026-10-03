// @copyright André Trettin

import CoreRPG
import Foundation

/// The shared `GenericEditController`: the never-read `selectionReference` was the only stored
/// state of its own. See CODE_AUDIT_Folder §9.2, §9.3.
typealias EditController = GenericEditController<GeneratorModel>

// MARK: - Module Editor

extension EditController {
    @MainActor func add(referenceId: UUID?, model: GeneratorModel) {
        model.referenceId = referenceId
        save(
            updated: model,
            message: String(localized: "Reference added", bundle: .module)
        )
    }
}
