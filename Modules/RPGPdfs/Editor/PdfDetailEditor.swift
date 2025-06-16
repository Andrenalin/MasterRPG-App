// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfDetailEditor: View {
    let editController: EditController
    let model: PdfModel

    @Environment(PdfRoot.self) private var root
    
    var body: some View {
        @Bindable var model = editController.model

        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)
            
#if !os(macOS)
            PdfEntrySectionEditor(editController: editController)
#endif
        } headerView: {
            PdfEditor(editController: editController)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(editController.model.id)
        } extHeaderView: {
            PdfExternalHeader(editController: editController)
        } extContentView: {
#if !os(tvOS)
            PdfEntryEditor(root: root, editController: editController)
#endif
        } extContentHeight: { screenHeight in
            let minHeight = Double(editController.model.entries.count * 128)
            return min(max(minHeight, screenHeight * 0.5), screenHeight)
        } heightCalculator: { size in
            (144, editController.model.hasPdf ? min(size.height * 0.35, 400) : 144)
        }

        .focusedSceneValue(\.selectedPdf, $model.id)
    }
}

struct PdfExternalHeader: View {
    let editController: EditController

    @Environment(PdfRoot.self) private var root
    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
        root.viewController.viewPdfInline(with: editController.model.id, withoutBookmark: false) {
            externalHeaderModel.showExtHeader = false
        }
        .id(editController.model.id)
    }
}

#Preview {
    PdfDetailEditor(editController: PdfRoot.previewWithData.editController(type: .main), model: .preview)
        .environment(PdfRoot.previewWithData)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
