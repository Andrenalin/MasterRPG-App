// @copyright André Trettin

import SwiftUI

struct NameItemEditor: View {
    let editController: any EditControllable
    
    @Environment(ListModel.self) private var itemListModel
    @Environment(\.wideMode) private var wideMode

    var body: some View {
        let _ = Self._printChanges()
        TextFieldModelEditor(editController: editController, model: editController.editorModel.nameTextFieldModel, title: wideMode == .small ? nil : "Name", prompt: "Enter a name for the item", bundle: .module, focusListner: true) {
            editController.reset(name: editController.editorModel.nameTextFieldModel.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: itemListModel.activeEdit, initial: true) {
            guard itemListModel.activeEdit else { return }
            itemListModel.activeEdit = false
            Task { @MainActor in
                try await Task.sleep(for: .seconds(0.75))
                editController.editorModel.activateFocus = true
            }
        }
        .onChange(of: editController.model.name) {
            guard editController.editorModel.currentItemId != nil else { return }
            editController.editorModel.nameTextFieldModel.text <=> editController.model.name
        }
    }
}
