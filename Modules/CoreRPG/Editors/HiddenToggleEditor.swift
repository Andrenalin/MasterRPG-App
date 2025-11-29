// @copyright André Trettin

import SwiftUI

struct HiddenToggleEditor: View {
    let editController: any EditControllable

    var body: some View {
        @Bindable var model = editController.editorModel.hiddenToggleModel
        ToggleModelEditor(editController: editController, model: model, bundle: .module)
            .onChange(of: model.state) {
                editController.reset(hidden: model.state)
            }
            .onChange(of: editController.model.isGroupHiddenToggle) {
                guard editController.editorModel.currentItemId != nil else { return }
                editController.editorModel.hiddenToggleModel.state <=> editController.model.isGroupHiddenToggle
            }
    }
}
