// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RerollEditor: View {
    let model: DiceModel

    @Environment(DiceRootModel.self) private var root

    @State private var rerollValue = 0.0
    @State private var replaceValue = 0.0
    @State private var isMaxDiceValue = false

    var body: some View {
        Section {
            rerollValueView

            rerollEditorView

            ToggleEditor(value: $isMaxDiceValue, title: isMaxDiceTitle, bundle: .module, icon: "123.rectangle")

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
        isMaxDiceValue ? "On: replace with max value" : "Off: replace with value"
    }

    @ViewBuilder
    var rerollValueView: some View {
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.rerollOptions) { reroll in
                        Button {
                            withAnimation(.easeInOut) { root.editController.remove(reroll: reroll, itemId: model.id) }
                        } label: {
                            HStack(spacing: 4) {
                                Label {
                                    Text(labelText(for: reroll), bundle: .module)
                                } icon: {
                                    Image(systemName: NetworkModules.dice.icon)
                                }
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
            Text("Re-roll", bundle: .module)
        }
    }

    func labelText(for reroll: DiceModel.RerollOption) -> LocalizedStringKey {
        if reroll.maxDiceValue {
            return "\(reroll.number) → Max Value"
        }
        return "\(reroll.number) → \(reroll.value)"
    }

    @ViewBuilder
    var rerollEditorView: some View {
        LabeledContent {
            HStack {
                Button {
                    addCurrentReroll()
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
                .padding(.horizontal, 16)
                .disabled(!isMaxDiceValue && rerollValue == 0)

                TextIntEditor(value: $rerollValue, title: "Re-roll Value", icon: "plus", prompt: "re-roll", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }

    func addCurrentReroll() {
        withAnimation(.easeInOut) {
            root.editController.add(reroll: Int(rerollValue), value: Int(replaceValue), isMaxDiceValue: isMaxDiceValue, itemId: model.id)
            rerollValue = 0.0
            replaceValue = 0.0
        }
    }

    @ViewBuilder
    var rerollReplaceEditorView: some View {
        LabeledContent {
            HStack {
                Button {
                    addCurrentReroll()
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
                .padding(.horizontal, 16)
                .disabled(rerollValue == 0 && replaceValue == 0)

                TextIntEditor(value: $replaceValue, title: "Replace Value", icon: "plus", prompt: "replace", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Replace", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    RerollEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
