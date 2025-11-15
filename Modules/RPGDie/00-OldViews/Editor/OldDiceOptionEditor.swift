// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct OldDiceOptionEditor: View {
    let editController: EditController

    var body: some View {
        @Bindable var model = editController.model
        Section {
            ToggleEditor(editController: editController, model: $model.sumUp, title: "Sum up dice", bundle: .module, icon: "sum")

            TextDoubleEditor(editController: editController, model: $model.modifier, title: "Modifier", icon: "plus.forwardslash.minus", prompt: "+/- 5", bundle: .module, range: -10...10)
                .padding(.bottom, 8)
            
            if model.canPercentDice {
                ToggleEditor(editController: editController, model: $model.percentDice, title: "Percent dice", bundle: .module, icon: "percent")
            }

            ValuePickerEditor(editController: editController, model: $model.compareOption, allCategories: DiceModel.CompareValue.allCases, title: "Check for", bundle: .module) { option in
                Text(option.text, bundle: .module)
                    .tag(option)

            }

            if model.compareOption != .off {
                TextDoubleEditor(editController: editController, model: $model.compareValue, title: "Value", icon: model.compareOption.icon, prompt: "Value to compare against", bundle: .module, range: -10...10)
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
}

#Preview("DS") {
    OldDiceOptionEditor(editController: .preview)
        .environment(DiceRootModel.preview)
}

#Preview("CoC") {
    OldDiceOptionEditor(editController: .preview)
        .environment(DiceRootModel.preview(id: DiceModel.uuidCoC))
}
