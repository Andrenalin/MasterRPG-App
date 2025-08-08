// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    weak var _root: PdfRootModel?
    var root: PdfRootModel {
        _root.unsafelyUnwrapped
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func pdfWindow(selection: ItemSelectionModel) -> some View {
        let model = root.itemController.modelSync(for: selection.itemId) ?? .newItem
        
        return PdfViewerView(editController: root.editController, model: model, entryId: selection.entryId, withoutBookmark: false)
            .navigationTitle(model.name)
            .environment(root)
    }

    @MainActor
    func viewPdfInline(with id: UUID, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.modelSync(for: id) ?? .newItem
        
        return PdfViewerView(editController: root.editController, model: model, withoutBookmark: withoutBookmark, toolbarClose: true, dismissAction: dismissAction)
            .environment(root)
    }
}
