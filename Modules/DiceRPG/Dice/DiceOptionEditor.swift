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
        Section {
            ToggleDiceValue(model: model, toggleKeyPath: \.sumUp, title: "Sum up dice", bundle: .module, icon: "sum", saveMessage: String(localized: "change sum up dice", bundle: .module))

            TextDoubleEditor(model: modifierEditModel, title: "Modifier", icon: "plus.forwardslash.minus", prompt: "+/- 5", bundle: .module, range: -10...10)
                .padding(.bottom, 8)

            if model.canPercentDice {
                ToggleDiceValue(model: model, toggleKeyPath: \.percentDice, title: "Percent dice", bundle: .module, icon: "percent", saveMessage: String(localized: "change percent", bundle: .module))
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
            syncAllEditModels()
        }
        // These three previously duplicated one line each of
        // `syncAllEditModels()` verbatim. See CODE_AUDIT §9.4.
        .onChange(of: model.modifier) {
            syncModifierEditModel()
        }
        .onChange(of: model.compareValue) {
            syncCompareValueEditModel()
        }
        .onChange(of: model.compareOption) {
            syncCompareOptionEditModel()
        }
    }

    private func syncAllEditModels() {
        syncModifierEditModel()
        syncCompareValueEditModel()
        syncCompareOptionEditModel()
    }

    private func syncModifierEditModel() {
        let editController = root.editController
        modifierEditModel.reset(valueId: model.id, value: model.modifier) { itemId, value in
            editController.reset(modifier: value, itemId: itemId)
        }
    }

    private func syncCompareValueEditModel() {
        let editController = root.editController
        compareValueEditModel.reset(valueId: model.id, value: model.compareValue) { itemId, value in
            editController.reset(compareValue: value, itemId: itemId)
        }
    }

    private func syncCompareOptionEditModel() {
        let editController = root.editController
        optionValueEditModel.reset(valueId: model.id, value: model.compareOption) { itemId, value in
            editController.reset(compareOption: value, itemId: itemId)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    DiceOptionEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
