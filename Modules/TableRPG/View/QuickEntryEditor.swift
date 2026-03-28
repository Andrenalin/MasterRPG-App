// @copyright André Trettin

import CoreRPG
import PdfRPG
import SwiftUI

struct QuickEntryEditor: View {
    let model: TableModel

    @Environment(TableRootModel.self) private var root

    @State private var referenceText = DebouncerModel(initialValue: "", delay: 2)

    var body: some View {
        QuickEntryEditorView(editController: root.editController, model: model, referenceText: referenceText, pdfEditorRoute: EditorRoute.selectionPdf) {
            EditorLinkView(root: root.rootController, model: model, editorLinkModel: root.editorLinkModel)
        } pdfOverlay: {
#if os(iOS) || os(tvOS)
            if let selectedPdf = root.editController.tableEditModel.selectionPdf.itemId {
                pdfOverlayView(selectedPdf: selectedPdf)
            }
#endif
        }
    }

    @ViewBuilder
    private func pdfOverlayView(selectedPdf: UUID) -> some View {
        root.pdfRoot.viewController.viewer(
            root: root.pdfRoot,
            itemId: selectedPdf,
            entryId: nil,
            configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false, aiExtractor: true),
            onTextExtracted: { text in
                withAnimation {
                    // Append to existing text or replace based on user preference
                    if referenceText.input.isEmpty {
                        referenceText.input = text
                    } else {
                        referenceText.input += "\n\n" + text
                    }
                }
            }
        ) {
            withAnimation { root.editController.tableEditModel.selectionPdf.resetSelection(itemId: nil, entryId: nil) }
        }
        .background(.primary)
    }
}
