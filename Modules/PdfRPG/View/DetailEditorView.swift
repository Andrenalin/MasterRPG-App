// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    DetailEditorView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

/// Exercises the "No file is set" branch. See CODE_AUDIT_Pdf §9.7.
#Preview("No file", traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    DetailEditorView(root: root, model: root.itemController.itemOrEmpty(for: PdfModel.previewEmptyId))
}

struct DetailEditorView: View {
    let root: PdfRootModel
    let model: PdfModel

    @State private var sheetRootModel: SheetRootModel?

    var body: some View {
        HStack {
            FileImporterView(
                editControllable: root.editController,
                fileTypes: root.editController.fileUrlDataController?.fileTypes ?? [],
                itemId: model.id,
                module: root.configurable.module
            )

            if let url = model.url {
                Text(verbatim: url.path(percentEncoded: false))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No file is set", bundle: .module)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(model.specialCategory ? 0 : 1)
        .allowsHitTesting(!model.specialCategory)
        .accessibilityHidden(model.specialCategory)
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
