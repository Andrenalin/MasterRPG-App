// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DiceOptionEditor: View {
    let model: DiceDataModel

    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        @Bindable var model = model
        Section {
            ToggleEditor(model: $model.sumUp, title: "Sum up dice", bundle: .module, icon: "sum")

            TextDoubleEditor(model: $model.modifier, title: "Modifier", icon: "plus.forwardslash.minus", prompt: "+/- 5", bundle: .module, range: -10...10)
                .padding(.bottom, 8)
            
            if model.canPercentDice {
                ToggleEditor(model: $model.percentDice, title: "Percent dice", bundle: .module, icon: "percent")
            }

            ValuePickerEditor(model: $model.compareOption, allCategories: DiceDataModel.CompareValue.allCases, title: "Check for", bundle: .module) { option in
                Text(option.text, bundle: .module)
                    .tag(option)

            }

            if model.compareOption != .off {
                TextDoubleEditor(model: $model.compareValue, title: "Value", icon: model.compareOption.icon, prompt: "Value to compare against", bundle: .module, range: 1...41)
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
    @Previewable @Query var models: [DiceDataModel]

    DiceOptionEditor(model: models.first!)
}
