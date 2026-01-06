// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ToggleDiceValue: View {
    let model: DiceModel
    let toggleKetpath: WritableKeyPath<DiceModel, Bool>
    
    var canToggle: Bool = true
    var title: LocalizedStringKey = "Hidden"
    var bundle: Bundle?
    var icon: String = "eye.slash"
    var saveMessage: String = "value toggle"
    
    @Environment(DiceRootModel.self) private var root
    
    @State private var toggleEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    
    var body: some View {
        let _ = Self._printChanges()
        ToggleEditor(model: toggleEditModel, canToggle: canToggle, title: title, bundle: bundle, icon: icon)
            .onChange(of: model, initial: true) {
                updateToggleValue()
            }
            .onChange(of: model[keyPath: toggleKetpath]) {
                updateToggleValue()
            }
    }
    
    func updateToggleValue() {
        let toggleValue = model[keyPath: toggleKetpath]
        guard model.id != toggleEditModel.valueId || toggleValue != toggleEditModel.value else { return }
        let editController = root.editController
        toggleEditModel.reset(valueId: model.id, value: toggleValue) { itemId, value in
            guard var item = root.editController.editModel(for: itemId) else { return }
            if value != item[keyPath: toggleKetpath] {
                item[keyPath: toggleKetpath] = value
                editController.save(updated: item, message: saveMessage)
            }
        }
    }
}
