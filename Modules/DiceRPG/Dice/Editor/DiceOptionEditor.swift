// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceOptionEditor: View {
    let model: DiceModel

    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        @Bindable var model = model
        Section {
            ToggleEditor(editController: root.editController, model: $model.sumUp, title: "Sum up dice", bundle: .module, icon: "sum")

            TextDoubleEditor(editController: root.editController, model: $model.modifier, title: "Modifier", icon: "plus.forwardslash.minus", prompt: "+/- 5", bundle: .module, range: -10...10)
                .padding(.bottom, 8)
            
            if model.canPercentDice {
                ToggleEditor(editController: root.editController, model: $model.percentDice, title: "Percent dice", bundle: .module, icon: "percent")
            }

            ValuePickerEditor(editController: root.editController, model: $model.compareOption, allCategories: DiceModel.CompareValue.allCases, title: "Check for", bundle: .module) { option in
                Text(option.text, bundle: .module)
                    .tag(option)

            }

            if model.compareOption != .off {
                TextDoubleEditor(editController: root.editController, model: $model.compareValue, title: "Value", icon: model.compareOption.icon, prompt: "Value to compare against", bundle: .module, range: 1...41)
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
