// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct RerollEditor: View {
    let model: DiceConfigDataModel
    
    @Environment(DiceRootModel.self) private var root

    @State private var currentReroll = 0
    @State private var currentValue = 0
    @State private var isMaxDiceValue = false

    var body: some View {
        Section {
            reroleValueView

            rerollEditorView

            ToggleEditor(model: $isMaxDiceValue, title: isMaxDiceTitle, bundle: .module, icon: "123.rectangle")

            if !isMaxDiceValue {
                rerollReplaceEditorView
            }
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Re-roll Options", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private extension RerollEditor {
    var isMaxDiceTitle: LocalizedStringKey {
        isMaxDiceValue ? "On: preplace with max value" : "Off: replace with value"
    }

    @ViewBuilder
    var reroleValueView: some View {
        @Bindable var model = model
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.rerollOptions) { reroll in
                        Button {
                            root.editController.remove(reroll: reroll, from: model)
                        } label: {
                            HStack(spacing: 8) {
                                Label {
                                    Text(labelText(for: reroll), bundle: .module)
                                } icon: {
                                    Image(systemName: NetworkModules.dice.icon)
                                }
                                Image(systemName: "x.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        //.borderLessTVBottonStyle()
                        .padding(4)
                    }
                }
            }
        } label: {
            Text("Re-roll", bundle: .module)
        }
    }
    
    func labelText(for reroll: DiceConfigDataModel.RerollOption) -> LocalizedStringKey {
        if reroll.maxDiceValue {
            return "\(reroll.number) --> Max Value"
        }
        return "\(reroll.number) --> \(reroll.value)"
    }

    var rerollText: Binding<String> {
        Binding {
            "\(currentReroll)"
        } set: {
            if let number = Int($0) {
                currentReroll = number
            }
        }
    }

    var rerollDouble: Binding<Double> {
        Binding {
            Double(currentReroll)
        } set: {
            currentReroll = Int($0)
        }
    }

    @ViewBuilder
    var rerollEditorView: some View {
        @Bindable var model = model
        LabeledContent {
            HStack {
                Button {
                    Task {
                        await addCurrentReroll()
                    }
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
                .padding(.horizontal, 16)
                .disabled(!isMaxDiceValue && currentReroll == 0)

                TextIntEditor(model: $currentReroll, title: "Re-roll Value", icon: "plus", prompt: "re-roll", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }

    func addCurrentReroll() async {
        withAnimation {
            root.editController.add(reroll: currentReroll, value: currentValue, isMaxDiceValue: isMaxDiceValue, to: model)
            currentReroll = 0
            currentValue = 0
        }
    }

    var rerollValueText: Binding<String> {
        Binding {
            "\(currentValue)"
        } set: {
            if let number = Int($0) {
                currentValue = number
            }
        }
    }

    var rerollValueDouble: Binding<Double> {
        Binding {
            Double(currentValue)
        } set: {
            currentValue = Int($0)
        }
    }

    @ViewBuilder
    var rerollReplaceEditorView: some View {
        @Bindable var model = model
        LabeledContent {
            HStack {
                Button {
                    Task {
                        await addCurrentReroll()
                    }
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
                .padding(.horizontal, 16)
                .disabled(currentReroll == 0 && currentValue == 0)

                TextIntEditor(model: $currentValue, title: "Replace Value", icon: "plus", prompt: "replace", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Replace", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceConfigDataModel]

    RerollEditor(model: models.first!)
}
