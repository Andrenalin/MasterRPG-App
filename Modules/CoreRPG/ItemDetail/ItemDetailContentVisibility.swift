// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

extension ItemRootControllable {
    /// Whether the detail screen shows the item's content: it has a file, or its module has no
    /// file types, or it is a folder or collection. Shared by the detail root and content views.
    /// See CODE_AUDIT_26 §9.22.
    func showsContent(of model: any ItemDataAccessible) -> Bool {
        let fileTypes = editControllable.fileUrlDataController?.fileTypes ?? []
        return model.url != nil || fileTypes.isEmpty || model.specialCategory
    }
}
