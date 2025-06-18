// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfEntryEditContent: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<PdfModel>

    @Environment(PdfRoot.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var model = editController.model
        TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the bookmark", bundle: .module)

        TextFieldEditor(editController: editController, model: $model[entryId].content, title: "Content", prompt: "Enter some content for the bookmark", bundle: .module)
    }
}

private extension PdfEntryEditContent {
    var entryId: UUID {
        entrySectionSelectionModel.id
    }
}
