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
                root.pdfRoot.viewController.inlineViewer(root: root.pdfRoot, with: selectedPdf, entryId: nil, withoutBookmark: true) {
                    withAnimation { root.editController.tableEditModel.selectionPdf.resetSelection(itemId: nil, entryId: nil) }
                }
                .background(.primary)
//                .pdfViewerActions(PdfViewerActions(selectedText: usePdfSelection(selection:)))
            }
#endif
        }
    }
    
//    private func usePdfSelection(selection: NSAttributedString) {
//        withAnimation { referenceText.input.append(selection.string) }
//    }
}
