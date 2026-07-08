// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailEditorView: View {
    let root: PdfRootModel
    let model: PdfModel

    @State private var sheetRootModel: SheetRootModel?

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
        .onChange(of: model.id, initial: true) {
            if sheetRootModel == nil {
                let rootController = root.rootController
                guard let rootManager = rootController.rootManager else { return }

                sheetRootModel = SheetRootModel(
                    rootManager: rootManager,
                    linkControllable: rootController.linkControllable,
                    sheetControllable: rootController.sheetControllable,
                    itemId: model.id,
                    isEditor: true,
                    editorModel: root.editController.editorModel.sheetEditorModel
                )
            } else {
                sheetRootModel?.reset(itemId: model.id)
            }
        }

        if let sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Bookmarks", bundle: .module).localizedString,
                linkTypes: LinkPdfModuleTransferable.self
            )
        }
    }
}
