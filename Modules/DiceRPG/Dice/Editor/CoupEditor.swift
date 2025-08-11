// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct CoupEditor: View {
    let model: DiceDataModel
    
    @Environment(DiceRootModel.self) private var root

    @State private var currentCoup = 0
    @State private var isDiceValueCoup = false

    var body: some View {
        @Bindable var config = model.config
        Section {
            coupValueView

            ToggleEditor(model: $config.coupOnlyOnFirstDie, title: "Only first die can coup", bundle: .module, icon: "dice")
                .disabled(config.coupValues.contains(where: { $0.isResult }))

            coupEditorView

            ToggleEditor(model: $isDiceValueCoup, title: isCoupMatchTitle, bundle: .module, icon: "123.rectangle")
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
        @Bindable var config = model.config
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(config.coupValues) { coup in
                        Button {
                            withAnimation { root.editController.remove(coup: coup, from: model) }
                        } label: {
                            HStack(spacing: 8) {
                                Label(coup.text, systemImage: coup.icon)
                                Image(systemName: "x.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(4)
                    }
                }
            }
        } label: {
            Text("Coup", bundle: .module)
        }
    }

    var coupValueText: Binding<String> {
        Binding {
            "\(currentCoup)"
        } set: {
            if let number = Int($0) {
                currentCoup = number
            }
        }
    }

    var coupValueDouble: Binding<Double> {
        Binding {
            Double(currentCoup)
        } set: {
            currentCoup = Int($0)
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
        @Bindable var config = model.config

        Button {
            addCurrentCoup()
        } label: {
            Image(systemName: "plus")
                .imageScale(.large)
        }
        .padding(.horizontal, 16)
        .disabled(currentCoup == 0)

        TextIntEditor(model: $currentCoup, title: "Coup Dice Value", icon: "plus", prompt: "coup", bundle: .module, range: config.minValue...config.maxValue)
    }

    func addCurrentCoup() {
        withAnimation {
            root.editController.add(coup: currentCoup, isDiceValueCoup: isDiceValueCoup, to: model)
            currentCoup = 0
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]

    CoupEditor(model: models.first!)
}
