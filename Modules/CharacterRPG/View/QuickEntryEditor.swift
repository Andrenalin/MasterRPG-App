// @copyright André Trettin

import CoreRPG
import PdfRPG
import SwiftUI

struct QuickEntryEditor: View {
    let model: ValueModel
    
    @Environment(CharacterRootModel.self) private var root
    
    @State private var referenceText = DebouncerModel(initialValue: "", delay: 2)

    var body: some View {
        QuickEntryEditorView(editController: root.editController, model: model, referenceText: referenceText, pdfEditorRoute: EditorRoute.selectionPdf) {
            EditorLinkView(root: root.rootController, model: model, editorLinkModel: root.editorLinkModel)
        } pdfOverlay: {
#if os(iOS) || os(tvOS)
            if let selectedPdf = root.editController.valueEditModel.selectionPdf.itemId {
                root.pdfRoot.viewController.viewer(root: root.pdfRoot, itemId: selectedPdf, entryId: nil, configuration: ViewerConfiguration(closeButton: false, addToolbar: false, isGame: false), withoutBookmark: true) {
                    withAnimation { root.editController.valueEditModel.selectionPdf.resetSelection(itemId: nil, entryId: nil) }
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
