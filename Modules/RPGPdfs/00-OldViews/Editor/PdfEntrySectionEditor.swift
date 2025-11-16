// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(PdfRootModel.self) private var root
    @State private var entrySectionEditorModel = EntrySectionEditorModel<PdfModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) {
            PdfEntryEditContent(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } contentView: {
            PdfEntryEditRow(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } showLinkView: {
            EmptyView()
        } swipeActionView: {
            EmptyView()
        } menuView: {
            EmptyView()
        } linkActionView: {
            EmptyView()
        }
    }
}

#Preview {
    PdfEntrySectionEditor(editController: .preview)
        .environment(PdfRootModel.preview)
        .environment(ListModel.preview)
}
