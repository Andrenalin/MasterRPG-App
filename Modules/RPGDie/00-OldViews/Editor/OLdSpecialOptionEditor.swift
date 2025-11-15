// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct OLdSpecialOptionEditor: View {
    let editController: EditController
    
    var body: some View {
        @Bindable var model = editController.model
        Section {
            ToggleEditor(editController: editController, model: $model.reorderDice, title: "Reorder dice by value", bundle: .module, icon: "textformat.123")

            ToggleEditor(editController: editController, model: addDiceActivate, title: "Add dice", bundle: .module, icon: "dice")

            if addDiceActivate.wrappedValue {
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

private extension OLdSpecialOptionEditor {
    var addDiceActivate: Binding<Bool> {
        Binding {
            editController.model.addDiceEvery > 0
        } set: {
            if $0 {
                let newMax = editController.model.entries.first?.die.max ?? 20
                if newMax != editController.model.addDiceEvery {
                    editController.model.addDiceEvery = newMax
                    editController.save(with: String(localized: "Change add dice every").localizedString)
                }
            } else {
                if editController.model.addDiceEvery != 0 {
                    editController.model.addDiceEvery = 0
                    editController.save(with: String(localized: "Change add dice every").localizedString)
                }
            }
        }
    }

    @ViewBuilder
    var addDiceEditorView: some View {
        @Bindable var model = editController.model
        LabeledContent {
            TextIntEditor(editController: editController, model: $model.addDiceEvery, title: "Add Dice each Value", icon: "plus", prompt: "value", bundle: .module, range: model.minValue...model.maxValue)
        } label: {
            Text("Add", bundle: .module)
        }
    }
}

#Preview {
    OLdSpecialOptionEditor(editController: .preview)
        .environment(DiceRootModel.preview)
}
