// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct OLdCoupEditor: View {
    let editController: EditController

    @State private var currentCoup = 0
    @State private var isDiceValueCoup = false

    var body: some View {
        @Bindable var model = editController.model
        Section {
            coupValueView

            ToggleEditor(editController: editController, model: $model.coupOnlyOnFirstDie, title: "Only first die can coup", bundle: .module, icon: "dice")
                .disabled(model.coupValues.contains(where: { $0.isResult }))

            coupEditorView

            ToggleEditor(editController: editController, model: $isDiceValueCoup, title: "Off match value with all dice, on match with one die", bundle: .module, icon: "123.rectangle")
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

    @ViewBuilder
    var coupValueView: some View {
        @Bindable var model = editController.model
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.coupValues) { coup in
                        Button {
                            Task {
                                await editController.remove(coup: coup)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Label(coup.text, systemImage: coup.icon)
                                Image(systemName: "x.circle.fill")
                                    .foregroundStyle(Color.accentColor)
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
        @Bindable var model = editController.model

        Button {
            Task {
                await addCurrentCoup()
            }
        } label: {
            Image(systemName: "plus")
                .imageScale(.large)
        }
        .padding(.horizontal, 16)
        .disabled(currentCoup == 0)

        TextIntEditor(editController: editController, model: $currentCoup, title: "Coup Dice Value", icon: "plus", prompt: "coup", bundle: .module, range: model.minValue...model.maxValue)
    }

    func addCurrentCoup() async {
        await editController.add(coup: currentCoup, isDiceValueCoup: isDiceValueCoup)
        withAnimation {
            currentCoup = 0
        }
    }
}

#Preview {
    OLdCoupEditor(editController: .preview)
        .environment(DiceRootModel.preview)
}
