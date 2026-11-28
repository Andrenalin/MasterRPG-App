// @copyright André Trettin

import CoreRPG
import PdfRPG
import SwiftUI

/// The shared `PdfQuickEntryEditor` with this module's types. See CODE_AUDIT_Edit_Save §9.6.
struct QuickEntryEditor: View {
    let model: AdventureModel

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        PdfQuickEntryEditor(
            rootController: root.rootController,
            editController: root.editController,
            model: model,
            editorLinkModel: root.editorLinkModel,
            pdfRoot: root.pdfRoot,
            pdfEditorRoute: AdventureEditorRoute.selectionPdf,
            selectionPdf: root.editController.adventureEditModel.selectionPdf
        )
    }
}

#Preview(traits: .mockData) { QuickEntryEditor(model: .preview) }
