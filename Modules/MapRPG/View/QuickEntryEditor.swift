// @copyright André Trettin

import CoreRPG
import PdfRPG
import SwiftUI

/// The shared `PdfQuickEntryEditor` with this module's types. See CODE_AUDIT_Edit_Save §9.6.
struct QuickEntryEditor: View {
    let model: MapModel

    @Environment(MapRootModel.self) private var root

    var body: some View {
        PdfQuickEntryEditor(
            rootController: root.rootController,
            editController: root.editController,
            model: model,
            editorLinkModel: root.editorLinkModel,
            pdfRoot: root.pdfRoot,
            pdfEditorRoute: MapEditorRoute.selectionPdf,
            selectionPdf: root.editController.mapEditModel.selectionPdf
        )
    }
}

#Preview(traits: .mockData) { QuickEntryEditor(model: .preview) }
