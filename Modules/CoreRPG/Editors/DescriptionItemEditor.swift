// @copyright André Trettin

import SwiftUI

struct DescriptionItemEditor: View {
    let editController: any EditControllable
    
    @Environment(ListModel.self) private var itemListModel
    @Environment(\.wideMode) private var wideMode

    var body: some View {
        TextFieldModelEditor(editController: editController, model: editController.editorModel.descriptionTextFieldModel, title: wideMode == .small ? nil : "Description", prompt: "Fill in some description for the item", bundle: .module) {
            editController.reset(description: editController.editorModel.descriptionTextFieldModel.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: editController.model.description) {
            guard editController.editorModel.currentItemId != nil else { return }
            editController.editorModel.descriptionTextFieldModel.text <=> editController.model.description
        }
    }
}
