// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let root: PdfRootModel
    let model: PdfModel

    var body: some View {
        HStack {
            FileImporterView(
                editControllable: root.editController,
                fileTypes: root.editController.fileUrlDataController?.fileTypes ?? [],
                itemId: model.id
            )

            Text(model.url?.path(percentEncoded: false) ?? "No file is set")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(model.specialCategory ? 0 : 1)
        .padding()

        SheetRootEditorView(
            root: root.rootController,
            linkControllable: root.linkControllable,
            editorModel: root.editController.sheetEditorModel,
            model: model,
            module: root.config.module,
            headerTitle: String(localized: "Bookmarks", bundle: .module).localizedString,
            linkTypes: LinkPdfModuleTransferable.self
        )
    }
}
