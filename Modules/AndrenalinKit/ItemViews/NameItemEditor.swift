// @copyright André Trettin

import SwiftUI

struct NameItemEditor: View {
    internal init(editController: any EditControllable) {
        self.editController = editController
        self._name = State(wrappedValue: editController.model.name)
    }
    
    let editController: any EditControllable
    
    @Environment(ListModel.self) private var itemListModel
    @Environment(\.wideMode) private var wideMode

    @State private var name: String = ""

    var body: some View {
        TextFieldEditor(editController: editController, model: $name, title: wideMode == .small ? nil : "Name", prompt: "Enter a name for the item", bundle: .module, focusListner: true) {
            editController.reset(name: name)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: itemListModel.activeEdit, initial: true) {
            guard itemListModel.activeEdit else { return }
            itemListModel.activeEdit = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                editController.editorModel.activateFocus = true
            }
        }
        .onChange(of: editController.model.name) {
            guard editController.editorModel.currentItemId != nil else { return }
            name = editController.model.name
        }
    }
}
