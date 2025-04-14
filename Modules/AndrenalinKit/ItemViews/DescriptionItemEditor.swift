// @copyright André Trettin

import SwiftUI

struct DescriptionItemEditor: View {
    internal init(editController: any EditControllable) {
        self.editController = editController
        self._description = State(wrappedValue: editController.model.description)
    }
    
    let editController: any EditControllable
    
    @Environment(ListModel.self) private var itemListModel
    @Environment(\.wideMode) private var wideMode

    @State private var description: String = ""

    var body: some View {
        TextFieldEditor(editController: editController, model: $description, title: wideMode == .small ? nil : "Description", prompt: "Fill in some description for the item", bundle: .module) {
            editController.reset(description: description)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: editController.model.description) {
            guard editController.editorModel.currentItemId != nil else { return }
            description = editController.model.description
        }
    }
}
