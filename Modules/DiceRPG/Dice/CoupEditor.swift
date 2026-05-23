// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CoupEditor: View {
    let model: DiceModel
    
    @Environment(DiceRootModel.self) private var root

    @State private var isDiceValueCoup = false
    @State private var coupValue = 0.0
    
    var body: some View {
        Section {
            coupValueView

            ToggleDiceValue(model: model, toggleKetpath: \.coupOnlyOnFirstDie, title: "Only first die can coup", bundle: .module, icon: "dice", saveMessage: String(localized: "change coup option", bundle: .module).localizedString)
                .disabled(model.coupValues.contains(where: { $0.isResult }))

            coupEditorView

            ToggleEditor(value: $isDiceValueCoup, title: isCoupMatchTitle, bundle: .module, icon: "123.rectangle")
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Coup Options", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    var isCoupMatchTitle: LocalizedStringKey {
        isDiceValueCoup ? "On: match with one die" : "Off: match value with all dice"
    }

    @ViewBuilder
    var coupValueView: some View {
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.coupValues) { coup in
                        Button {
                            withAnimation { root.editController.remove(coup: coup, itemId: model.id) }
                        } label: {
                            HStack(spacing: 4) {
                                Label(coup.text, systemImage: coup.icon)
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
            Text("Coup", bundle: .module)
        }
    }

    @ViewBuilder
    var coupEditorView: some View {
        LabeledContent {
            HStack {
                addView
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }
    
    @ViewBuilder
    var addView: some View {
        Button {
            addCurrentCoup()
        } label: {
            Image(systemName: "plus")
                .imageScale(.large)
        }
        .padding(.horizontal, 16)
        .disabled(coupValue == 0)

        TextIntEditor(value: $coupValue, title: "Coup Dice Value", icon: "plus", prompt: "coup", bundle: .module, range: model.minValue...model.maxValue)
    }

    func addCurrentCoup() {
        withAnimation(.easeInOut) {
            root.editController.add(coup: Int(coupValue), isDiceValueCoup: isDiceValueCoup, itemId: model.id)
            coupValue = 0.0
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    CoupEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
