// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct FumbleEditor: View {
    let model: DiceDataModel
    
    @Environment(DiceRootModel.self) private var root

    @State private var currentFumble = 0
    @State private var isDiceValueFumble = false
    
    var body: some View {
        @Bindable var config = model.config
        Section {
            fumbleValueView
            
            ToggleEditor(model: $config.fumbleOnlyOnFirstDie, title: "Only first die can fumble", bundle: .module, icon: "dice")
                .disabled(config.fumbleValues.contains(where: { $0.isResult }))
            
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
        @Bindable var config = model.config
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(config.fumbleValues) { fumble in
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
        @Bindable var config = model.config
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

                TextIntEditor(model: $currentFumble, title: "Fumble Dice Value", icon: "plus", prompt: "fumble", bundle: .module, range: config.minValue...config.maxValue)
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
    @Previewable @Query var models: [DiceDataModel]

    FumbleEditor(model: models.first!)
}
