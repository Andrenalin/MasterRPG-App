// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct SpecialOptionEditor: View {
    let model: DiceDataModel
    
    @Environment(DiceRootModel.self) private var root

    var body: some View {
        @Bindable var config = model.config
        Section {
            ToggleEditor(model: $config.reorderDice, title: "Reorder dice by value", bundle: .module, icon: "textformat.123")

            ToggleEditor(model: $config.addDiceActivate, title: "Add dice", bundle: .module, icon: "dice")

            if config.addDiceActivate {
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
        @Bindable var config = model.config
        LabeledContent {
            TextIntEditor(model: $config.addDiceEvery, title: "Add Dice each Value", icon: "plus", prompt: "value", bundle: .module, range: config.minValue...config.maxValue)
        } label: {
            Text("Add", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]

    SpecialOptionEditor(model: models.first!)
}
