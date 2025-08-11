// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DiceOptionEditor: View {
    let model: DiceDataModel

    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        
        @Bindable var config = model.config
        Section {
            ToggleEditor(editController: root.editController, model: $config.sumUp, title: "Sum up dice", bundle: .module, icon: "sum")

//            TextDoubleEditor(editController: editController, model: $model.modifier, title: "Modifier", icon: "plus.forwardslash.minus", prompt: "+/- 5", bundle: .module, range: -10...10)
//                .padding(.bottom, 8)
//            
//            if model.canPercentDice {
//                ToggleEditor(editController: editController, model: $model.percentDice, title: "Percent dice", bundle: .module, icon: "percent")
//            }
//
//            ValuePickerEditor(editController: editController, model: $model.compareOption, allCategories: DiceModel.CompareValue.allCases, title: "Check for", bundle: .module) { option in
//                Text(option.text, bundle: .module)
//                    .tag(option)
//
//            }
//
//            if model.compareOption != .off {
//                TextDoubleEditor(editController: editController, model: $model.compareValue, title: "Value", icon: model.compareOption.icon, prompt: "Value to compare against", bundle: .module, range: -10...10)
//            }
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
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]

    DiceOptionEditor(model: models.first!)
}
