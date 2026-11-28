// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The quick entry editor of a module that extracts entries from a PDF (Adventure, Character,
/// Map, Table): the link inspector and, on iOS/tvOS, the selected PDF over the editor. The four
/// modules kept copies of this view that differed only in their types, route and selection
/// model, so every fix had to be repeated four times. See CODE_AUDIT_Edit_Save §9.6.
public struct PdfQuickEntryEditor<EditController: EntryDataEditable>: View {
    public init(
        rootController: ItemRootController,
        editController: EditController,
        model: EditController.Model,
        editorLinkModel: EditorLinkModel,
        pdfRoot: PdfRootModel,
        pdfEditorRoute: any NavigationDestination,
        selectionPdf: ItemSelectionModel
    ) {
        self.rootController = rootController
        self.editController = editController
        self.model = model
        self.editorLinkModel = editorLinkModel
        self.pdfRoot = pdfRoot
        self.pdfEditorRoute = pdfEditorRoute
        self.selectionPdf = selectionPdf
    }

    let rootController: ItemRootController
    let editController: EditController
    let model: EditController.Model
    let editorLinkModel: EditorLinkModel
    let pdfRoot: PdfRootModel
    let pdfEditorRoute: any NavigationDestination
    let selectionPdf: ItemSelectionModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var referenceText = DebouncerModel(initialValue: "", delay: DebounceDelay.quickEntryEditor)

    public var body: some View {
        QuickEntryEditorView(root: rootController, editController: editController, model: model, referenceText: referenceText, pdfEditorRoute: pdfEditorRoute) {
            EditorLinkView(root: rootController, model: model, editorLinkModel: editorLinkModel)
        } pdfOverlay: {
#if os(iOS) || os(tvOS)
            if let selectedPdf = selectionPdf.itemId {
                pdfOverlayView(selectedPdf: selectedPdf)
            }
#endif
        }
    }

    @ViewBuilder
    private func pdfOverlayView(selectedPdf: UUID) -> some View {
        pdfRoot.viewController.viewer(
            root: pdfRoot,
            itemId: selectedPdf,
            entryId: nil,
            configuration: ViewerConfiguration(closeButton: false, addToolbar: true, isGame: false, aiExtractor: true)
        ) {
            withAnimation(reduceMotion ? nil : .default) {
                selectionPdf.resetSelection(itemId: nil, entryId: nil)
            }
        }
        .background(.primary)
    }
}
