// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct FumbleEditor: View {
    let model: DiceConfigDataModel
    
    @Environment(DiceRootModel.self) private var root

    @State private var currentFumble = 0
    @State private var isDiceValueFumble = false
    
    var body: some View {
        @Bindable var model = model
        Section {
            fumbleValueView
            
            ToggleEditor(model: $model.fumbleOnlyOnFirstDie, title: "Only first die can fumble", bundle: .module, icon: "dice")
                .disabled(model.fumbleValues.contains(where: { $0.isResult }))
            
            fumbleEditorView
            
            ToggleEditor(model: $isDiceValueFumble, title: isFumbleMatchTitle, bundle: .module, icon: "123.rectangle")
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
                HStack(spacing: 4) {
                    ForEach(model.fumbleValues) { fumble in
                        Button {
                            withAnimation { root.editController.remove(fumble: fumble, from: model) }
                        } label: {
                            HStack(spacing: 8) {
                                Label(fumble.text, systemImage: fumble.icon)
                                Image(systemName: "x.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(4)
                    }
                }
            }
        } label: {
            Text("Fumble", bundle: .module)
        }
    }

    var fumbleValueText: Binding<String> {
        Binding {
            "\(currentFumble)"
        } set: {
            if let number = Int($0) {
                currentFumble = number
            }
        }
    }

    var fumbleValueDouble: Binding<Double> {
        Binding {
            Double(currentFumble)
        } set: {
            currentFumble = Int($0)
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
                .disabled(currentFumble == 0)

                TextIntEditor(model: $currentFumble, title: "Fumble Dice Value", icon: "plus", prompt: "fumble", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }

    func addCurrentFumble() async {
        withAnimation {
            root.editController.add(fumble: currentFumble, isDiceValueFumble: isDiceValueFumble, to: model)
            currentFumble = 0
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceConfigDataModel]

    FumbleEditor(model: models.first!)
}
