// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SpecialOptionEditor: View {
    let model: DiceModel
    
    @Environment(DiceRootModel.self) private var root

    var body: some View {
        @Bindable var model = model
        Section {
            ToggleEditor(editController: root.editController, model: $model.reorderDice, title: "Reorder dice by value", bundle: .module, icon: "textformat.123")

            ToggleEditor(editController: root.editController, model: $model.addDiceActivate, title: "Add dice", bundle: .module, icon: "dice")

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
    }
}

private extension SpecialOptionEditor {

    @ViewBuilder
    var addDiceEditorView: some View {
        @Bindable var model = model
        LabeledContent {
            TextIntEditor(editController: root.editController, model: $model.addDiceEvery, title: "Add Dice each Value", icon: "plus", prompt: "value", bundle: .module, range: model.minFirstValue...model.maxFirstValue)
        } label: {
            Text("Add", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    SpecialOptionEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
