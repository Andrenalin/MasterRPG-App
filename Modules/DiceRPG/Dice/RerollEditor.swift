// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RerollEditor: View {
    let model: DiceModel

    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rerollValue = 0.0
    @State private var replaceValue = 0.0
    @State private var isMaxDiceValue = false

    var body: some View {
        Section {
            RerollEditorRerollValueView(rerollOptions: model.rerollOptions, reduceMotion: reduceMotion, onRemove: { reroll in
                root.editController.remove(reroll: reroll, itemId: model.id)
            })

            RerollEditorRerollEditorView(model: model, isMaxDiceValue: isMaxDiceValue, rerollValue: $rerollValue, onAddReroll: addCurrentReroll)

            ToggleEditor(value: $isMaxDiceValue, title: isMaxDiceTitle, bundle: .module, icon: "123.rectangle")

            if !isMaxDiceValue {
                RerollEditorRerollReplaceEditorView(model: model, rerollValue: rerollValue, replaceValue: $replaceValue, onAddReplacement: addCurrentReroll)
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

    func addCurrentReroll() {
        withAnimation(reduceMotion ? nil : .easeInOut) {
            root.editController.add(reroll: Int(rerollValue), value: Int(replaceValue), isMaxDiceValue: isMaxDiceValue, itemId: model.id)
            rerollValue = 0.0
            replaceValue = 0.0
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct RerollEditorRerollValueView: View {
    let rerollOptions: [DiceModel.RerollOption]
    let reduceMotion: Bool
    let onRemove: (DiceModel.RerollOption) -> Void

    var body: some View {
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(rerollOptions) { reroll in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut) {
                                onRemove(reroll)
                            }
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
}

private struct RerollEditorRerollEditorView: View {
    let model: DiceModel
    let isMaxDiceValue: Bool
    @Binding var rerollValue: Double
    let onAddReroll: () -> Void

    var body: some View {
        LabeledContent {
            HStack {
                Button {
                    onAddReroll()
                } label: {
                    Label {
                        Text("Add reroll", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!isMaxDiceValue && rerollValue == 0)

                TextIntEditor(value: $rerollValue, title: "Re-roll Value", icon: "plus", prompt: "re-roll", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }
}

private struct RerollEditorRerollReplaceEditorView: View {
    let model: DiceModel
    let rerollValue: Double
    @Binding var replaceValue: Double
    let onAddReplacement: () -> Void

    var body: some View {
        LabeledContent {
            HStack {
                Button {
                    onAddReplacement()
                } label: {
                    Label {
                        Text("Add replacement", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                }
                .frame(minWidth: 44, minHeight: 44)
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
