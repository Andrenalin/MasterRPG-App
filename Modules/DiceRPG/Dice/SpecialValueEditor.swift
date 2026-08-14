// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Shared body for `CoupEditor` and `FumbleEditor`, which were structurally identical aside
/// from coup/fumble terminology and their remove-button animation curve. Every localized
/// string stays a literal at each call site (`CoupEditor`/`FumbleEditor`) and is only ever
/// passed in as an already-resolved `Text`/`LocalizedStringKey` — never rebuilt in here from
/// a runtime parameter — so String Catalog extraction still sees a static key per call site.
struct SpecialValueEditor: View {
    let model: DiceModel
    let values: [DiceModel.CoupFumbleOption]
    let toggleKeyPath: WritableKeyPath<DiceModel, Bool>
    let toggleTitle: LocalizedStringKey
    let toggleSaveMessage: String
    let sectionHeader: Text
    let valuesLabel: Text
    let addLabel: Text
    let valueFieldTitle: LocalizedStringKey
    let valueFieldPrompt: LocalizedStringKey
    let removeAnimation: Animation?
    let addAnimation: Animation?
    let onRemove: (DiceModel.CoupFumbleOption) -> Void
    let onAdd: (Int, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDiceValueMatch = false
    @State private var value = 0.0

    var body: some View {
        Section {
            valuesView

            ToggleDiceValue(model: model, toggleKeyPath: toggleKeyPath, title: toggleTitle, bundle: .module, icon: "dice", saveMessage: toggleSaveMessage)
                .disabled(values.contains(where: { $0.isResult }))

            editorView

            ToggleEditor(value: $isDiceValueMatch, title: matchTitle, bundle: .module, icon: "123.rectangle")
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            sectionHeader
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var matchTitle: LocalizedStringKey {
        isDiceValueMatch ? "On: match with one die" : "Off: match value with all dice"
    }

    @ViewBuilder
    private var valuesView: some View {
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(values) { item in
                        Button {
                            withAnimation(reduceMotion ? nil : removeAnimation) {
                                onRemove(item)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Label(item.text, systemImage: item.icon)
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
            valuesLabel
        }
    }

    @ViewBuilder
    private var editorView: some View {
        LabeledContent {
            HStack {
                Button {
                    addCurrentValue()
                } label: {
                    Label {
                        addLabel
                    } icon: {
                        Image(systemName: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(value == 0)

                TextIntEditor(value: $value, title: valueFieldTitle, icon: "plus", prompt: valueFieldPrompt, bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }

    private func addCurrentValue() {
        withAnimation(reduceMotion ? nil : addAnimation) {
            onAdd(Int(value), isDiceValueMatch)
            value = 0.0
        }
    }
}
