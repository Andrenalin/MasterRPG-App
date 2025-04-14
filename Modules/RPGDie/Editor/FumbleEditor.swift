// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct FumbleEditor: View {
    let editController: EditController
    
    @State private var currentFumble = 0
    @State private var isDiceValueFumble = false
    
    var body: some View {
        @Bindable var model = editController.model
        Section {
            fumbleValueView
            
            ToggleEditor(editController: editController, model: $model.fumbleOnlyOnFirstDie, title: "Only first die can fumble", bundle: .module, icon: "dice")
                .disabled(model.fumbleValues.contains(where: { $0.isResult }))
            
            fumbleEditorView
            
            ToggleEditor(editController: editController, model: $isDiceValueFumble, title: "Off match value with all dice, on match with one die", bundle: .module, icon: "123.rectangle")
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
    @ViewBuilder
    var fumbleValueView: some View {
        @Bindable var model = editController.model
        LabeledContent {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.fumbleValues) { fumble in
                        Button {
                            Task { await editController.remove(fumble: fumble) }
                        } label: {
                            HStack(spacing: 8) {
                                Label(fumble.text, systemImage: fumble.icon)
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
        @Bindable var model = editController.model
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

                TextIntEditor(editController: editController, model: $currentFumble, title: "Fumble Dice Value", icon: "plus", prompt: "fumble", bundle: .module, range: model.minValue...model.maxValue)
            }
            .labelsHidden()
        } label: {
            Text("Add", bundle: .module)
        }
    }

    func addCurrentFumble() async {
        await editController.add(fumble: currentFumble, isDiceValueFumble: isDiceValueFumble)
        withAnimation {
            currentFumble = 0
        }
    }
}

#Preview {
    FumbleEditor(editController: .preview)
        .environment(DiceRoot.preview)
}
