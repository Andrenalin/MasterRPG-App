// @copyright André Trettin

import CoreRPG
import SwiftUI

struct FumbleEditor: View {
    let model: DiceModel

    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDiceValueFumble = false
    @State private var fumbleValue: Double = 0.0

    var body: some View {
        Section {
            fumbleValueView

            ToggleDiceValue(model: model, toggleKetpath: \.fumbleOnlyOnFirstDie, title: "Only first die can fumble", bundle: .module, icon: "dice", saveMessage: String(localized: "change fumble option", bundle: .module).localizedString)
                .disabled(model.fumbleValues.contains(where: { $0.isResult }))

            fumbleEditorView

            ToggleEditor(value: $isDiceValueFumble, title: isFumbleMatchTitle, bundle: .module, icon: "123.rectangle")
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
                            withAnimation(reduceMotion ? nil : .easeInOut) {
                                root.editController.remove(fumble: fumble, itemId: model.id)
                            }
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
                    addCurrentFumble()
                } label: {
                    Label {
                        Text("Add fumble", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(fumbleValue == 0)

                TextIntEditor(value: $fumbleValue, title: "Fumble Dice Value", icon: "plus", prompt: "fumble", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }

    func addCurrentFumble() {
        withAnimation(reduceMotion ? nil : .easeInOut) {
            root.editController.add(fumble: Int(fumbleValue), isDiceValueFumble: isDiceValueFumble, itemId: model.id)
            fumbleValue = 0.0
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    FumbleEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
