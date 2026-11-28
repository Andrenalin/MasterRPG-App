// @copyright André Trettin

import CoreRPG
import PdfRPG
import SwiftUI

/// The shared `PdfQuickEntryEditor` with this module's types. See CODE_AUDIT_Edit_Save §9.6.
struct QuickEntryEditor: View {
    let model: ValueModel

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        PdfQuickEntryEditor(
            rootController: root.rootController,
            editController: root.editController,
            model: model,
            editorLinkModel: root.editorLinkModel,
            pdfRoot: root.pdfRoot,
            pdfEditorRoute: CharacterEditorRoute.selectionPdf,
            selectionPdf: root.editController.valueEditModel.selectionPdf
        )
    }
}

#Preview(traits: .mockData) { QuickEntryEditor(model: .preview) }
