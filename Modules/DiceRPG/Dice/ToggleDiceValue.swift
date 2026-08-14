// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    ToggleDiceValue(
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
        toggleKeyPath: \.sumUp
    )
    .padding()
}

struct ToggleDiceValue: View {
    let model: DiceModel
    let toggleKeyPath: WritableKeyPath<DiceModel, Bool>
    
    var canToggle: Bool = true
    var title: LocalizedStringKey = "Hidden"
    var bundle: Bundle?
    var icon: String = "eye.slash"
    var saveMessage: String = "value toggle"
    
    @Environment(DiceRootModel.self) private var root
    
    @State private var toggleEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    
    var body: some View {
        ToggleEditor(model: toggleEditModel, canToggle: canToggle, title: title, bundle: bundle, icon: icon)
            .onChange(of: model, initial: true) {
                updateToggleValue()
            }
            .onChange(of: model[keyPath: toggleKeyPath]) {
                updateToggleValue()
            }
    }
    
    func updateToggleValue() {
        let toggleValue = model[keyPath: toggleKeyPath]
        guard model.id != toggleEditModel.valueId || toggleValue != toggleEditModel.value else { return }
        let editController = root.editController
        toggleEditModel.reset(valueId: model.id, value: toggleValue) { itemId, value in
            guard var item = editController.editModel(for: itemId) else { return }
            if value != item[keyPath: toggleKeyPath] {
                item[keyPath: toggleKeyPath] = value
                editController.save(updated: item, message: saveMessage)
            }
        }
    }
}
