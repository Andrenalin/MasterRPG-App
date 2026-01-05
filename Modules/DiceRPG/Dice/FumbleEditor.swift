// @copyright André Trettin

import CoreRPG
import SwiftUI

struct FumbleEditor: View {
    let model: DiceModel
    
    @Environment(DiceRootModel.self) private var root

    @State private var isDiceValueFumble = false
    @State private var fumbleValueModel: EditIdentifierModel<Double> = EditIdentifierModel(value: 0.0)
    
    var body: some View {
        @Bindable var model = model
        Section {
            fumbleValueView
            
            ToggleEditor(editController: root.editController, model: $model.fumbleOnlyOnFirstDie, title: "Only first die can fumble", bundle: .module, icon: "dice")
                .disabled(model.fumbleValues.contains(where: { $0.isResult }))
            
            fumbleEditorView
            
            ToggleEditor(editController: root.editController, model: $isDiceValueFumble, title: isFumbleMatchTitle, bundle: .module, icon: "123.rectangle")
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Fumble Options", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private extension FumbleEditor {
    var isFumbleMatchTitle: LocalizedStringKey {
        isDiceValueFumble ? "On: match with one die" : "Off: match value with all dice"
    }

    @ViewBuilder
    var fumbleValueView: some View {
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.fumbleValues) { fumble in
                        Button {
                            withAnimation { root.editController.remove(fumble: fumble, itemId: model.id) }
                        } label: {
                            HStack(spacing: 4) {
                                Label(fumble.text, systemImage: fumble.icon)
                                Image(systemName: "x.circle.fill")
                                    .foregroundStyle(Color.red)
                                    .offset(y: -8)
                            }
                        }
                        .borderLessTVBottonStyle()
                        .padding(4)
                    }
                }
            }
        } label: {
            Text("Fumble", bundle: .module)
        }
    }

    @ViewBuilder
    var fumbleEditorView: some View {
        LabeledContent {
            HStack {
                Button {
                    Task {
                        await addCurrentFumble()
                    }
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
                .padding(.horizontal, 16)
                .disabled(fumbleValueModel.value == 0)

                TextIntEditor(model: fumbleValueModel, title: "Fumble Dice Value", icon: "plus", prompt: "fumble", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }

    func addCurrentFumble() async {
        withAnimation {
            root.editController.add(fumble: Int(fumbleValueModel.value), isDiceValueFumble: isDiceValueFumble, itemId: model.id)
            fumbleValueModel.reset(valueId: UUID(), value: 0.0, saveHandler: nil)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    FumbleEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
