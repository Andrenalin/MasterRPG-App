// @copyright André Trettin

import CoreRPG
import PdfRPG
import SwiftUI

struct QuickEntryEditor: View {
    let model: ValueModel
    
    @Environment(CharacterRootModel.self) private var root
    
    @State private var referenceText = DebouncerModel(initialValue: "", delay: 2)

    var body: some View {
        QuickEntryEditorView(root: root.rootController, editController: root.editController, model: model, referenceText: referenceText, pdfEditorRoute: CharacterEditorRoute.selectionPdf) {
            EditorLinkView(root: root.rootController, model: model, editorLinkModel: root.editorLinkModel)
        } pdfOverlay: {
#if os(iOS) || os(tvOS)
            if let selectedPdf = root.editController.valueEditModel.selectionPdf.itemId {
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
                    if referenceText.input.isEmpty {
                        referenceText.input = text
                    } else {
                        referenceText.input += "\n\n" + text
                    }
                }
            }
        ) {
            withAnimation { root.editController.valueEditModel.selectionPdf.resetSelection(itemId: nil, entryId: nil) }
        }
        .background(.primary)
        .pdfViewerActions(PdfViewerActions(selectedText: usePdfSelection(selection:)))
    }

    private func usePdfSelection(selection: NSAttributedString) {
        withAnimation { referenceText.input.append(selection.string) }
    }
}

#Preview(traits: .mockData) { QuickEntryEditor(model: .preview) }
