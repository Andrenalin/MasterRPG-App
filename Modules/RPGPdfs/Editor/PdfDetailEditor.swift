// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfDetailEditor: View {
    let editController: EditController
    let model: PdfModel

    @Environment(PdfRoot.self) private var root
    
    var body: some View {
        @Bindable var model = model

        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)
            
#if !os(macOS)
            PdfEntrySectionEditor(editController: editController)
#endif
        } headerView: { size, safeTopMargin, isInline in
            PdfEditor(editController: editController, size: size, topMargin: safeTopMargin, inline: isInline)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        } extHeaderView: { dismiss in
            root.viewController.viewPdfInline(with: model.id, withoutBookmark: false, dismissAction: dismiss)
                .id(model.id)
        } extContentView: {
#if !os(tvOS)
            PdfEntryEditor(root: root, editController: editController)
#endif
        } extContentHeight: { screenHeight in
            let minHeight = Double(model.entries.count * 128)
            return min(max(minHeight, screenHeight * 0.5), screenHeight)
        } heightCalculator: { size in
            (144, model.hasPdf ? min(size.height * 0.35, 400) : 144)
        }

        .focusedSceneValue(\.selectedPdf, $model.id)
    }
}

#Preview {
    PdfDetailEditor(editController: .preview, model: .preview)
        .environment(PdfRoot.preview)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
