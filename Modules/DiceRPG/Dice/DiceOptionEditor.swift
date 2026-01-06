// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceOptionEditor: View {
    let model: DiceModel

    @Environment(DiceRootModel.self) private var root
    
    @State private var modifierEditModel: EditIdentifierModel<Double> = EditIdentifierModel(value: 0.0)
    @State private var compareValueEditModel: EditIdentifierModel<Double> = EditIdentifierModel(value: 0.0)
    @State private var optionValueEditModel: EditIdentifierModel<DiceModel.CompareValue> = EditIdentifierModel(value: .off)

    var body: some View {
        @Bindable var model = model
        Section {
            ToggleDiceValue(model: model, toggleKetpath: \.sumUp, title: "Sum up dice", bundle: .module, icon: "sum", saveMessage: String(localized: "change sum up dice").localizedString)

            TextDoubleEditor(model: modifierEditModel, title: "Modifier", icon: "plus.forwardslash.minus", prompt: "+/- 5", bundle: .module, range: -10...10)
                .padding(.bottom, 8)
            
            if model.canPercentDice {
                ToggleDiceValue(model: model, toggleKetpath: \.percentDice, title: "Percent dice", bundle: .module, icon: "percent", saveMessage: String(localized: "change percent").localizedString)
            }

            ValuePickerEditor(model: optionValueEditModel, allCategories: DiceModel.CompareValue.allCases, title: "Check for", bundle: .module) { option in
                Text(option.text, bundle: .module)
            }

            if model.compareOption != .off {
                TextDoubleEditor(model: compareValueEditModel, title: "Value", icon: model.compareOption.icon, prompt: "Value to compare against", bundle: .module, range: 1...41)
            }
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Options", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: model.id, initial: true) {
            let editController = root.editController
            modifierEditModel.reset(valueId: model.id, value: model.modifier) { itemId, value in
                editController.reset(modifer: value, itemId: itemId)
            }
            compareValueEditModel.reset(valueId: model.id, value: model.compareValue) { itemId, value in
                editController.reset(compareValue: value, itemId: itemId)
            }
            optionValueEditModel.reset(valueId: model.id, value: model.compareOption) { itemId, value in
                editController.reset(compareOption: value, itemId: itemId)
            }
        }
    }
    
    var modifierRange: ClosedRange<Double> {
        let modifier = model.modifier
        let min = modifier - 10
        let max = modifier + 10
                
        return min...max
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    DiceOptionEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
