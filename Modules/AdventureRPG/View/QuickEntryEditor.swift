// @copyright André Trettin

import CoreRPG
import PdfRPG
import SwiftUI

struct QuickEntryEditor: View {
    @Environment(AdventureRootModel.self) private var root
    
    @State private var referenceText = DebouncerModel(initialValue: "", delay: 2)

    var body: some View {
        QuickEntryEditorView(editController: root.editController, referenceText: referenceText, pdfEditorRoute: EditorRoute.selectionPdf) {
            EditorLinkView()
        } pdfOverlay: {
#if os(iOS) || os(tvOS)
            if let selectedPdf = root.editController.adventureEditModel.selectionPdf.itemId {
                root.pdfRoot.viewController.inlineViewer(root: root.pdfRoot, with: selectedPdf, withoutBookmark: true) {
                    withAnimation { root.editController.adventureEditModel.selectionPdf.resetSelection(itemId: nil) }
                }
                .background(.primary)
                .pdfViewerActions(PdfViewerActions(selectedText: usePdfSelection(selection:)))
            }
#endif
        }
    }
    
    private func usePdfSelection(selection: NSAttributedString) {
        withAnimation { referenceText.input.append(selection.string) }
    }
}
