// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SpecialOptionEditor: View {
    let model: DiceModel
    
    @Environment(DiceRootModel.self) private var root

    @State private var addValueModel: EditIdentifierModel<Double> = EditIdentifierModel(value: 0.0)
    
    var body: some View {
        @Bindable var model = model
        Section {
            ToggleDiceValue(model: model, toggleKetpath: \.reorderDice, title: "Reorder dice by value", bundle: .module, icon: "textformat.123", saveMessage: String(localized: "change reorder dice option", bundle: .module).localizedString)

            ToggleDiceValue(model: model, toggleKetpath: \.addDiceActivate, title: "Add dice", bundle: .module, icon: "dice", saveMessage: String(localized: "change add dice", bundle: .module).localizedString)

            if model.addDiceActivate {
                addDiceEditorView
            }
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Special Options", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: model.id, initial: true) {
            let editController = root.editController
            addValueModel.reset(valueId: model.id, value: Double(model.addDiceEvery)) { itemId, value in
                editController.reset(addValue: value, itemId: itemId)
            }
        }

    }
}

private extension SpecialOptionEditor {

    @ViewBuilder
    var addDiceEditorView: some View {
        @Bindable var model = model
        LabeledContent {
            TextIntEditor(model: addValueModel, title: "Add Dice each Value", icon: "plus", prompt: "value", bundle: .module, range: model.minFirstValue...model.maxFirstValue)
        } label: {
            Text("Add", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    SpecialOptionEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
