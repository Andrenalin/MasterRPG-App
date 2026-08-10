// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    DiceQuickEditor(itemId: DiceModel.previewId) { _ in }
}

struct DiceQuickEditor: View {
    init(itemId: UUID, action: @escaping (Int) async -> Void) {
        self.itemId = itemId
        self.action = action
    }

    let itemId: UUID
    let action: (Int) async -> Void

    @Environment(DiceRootModel.self) private var root

    @State private var value: String = ""
    @FocusState private var isFocused: Bool

    private var valueIntBinding: Binding<Int> {
        Binding {
            Int(value) ?? 0
        } set: { newValue in
            value = String("\(newValue)")
        }
    }

    var body: some View {
        VStack {
            VStack {
                rowMinusButtonsView
                rowPlusButtonsView
            }
            .rowEditColor()

            HStack {
                TextField(text: $value) {
                    Text("Compare Value", bundle: .module)
                }
                .numericInput($value, includeDecimal: false)
                .textFieldStyle(.plain)
                .labelsHidden()
                .accessibilityLabel(Text("Compare Value", bundle: .module))
                .padding(4)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit {
                    Task {
                        await action(Int(value) ?? 0)
                    }
                }

                Button {
                    Task {
                        await action(Int(value) ?? 0)
                    }
                } label: {
                    Label {
                        Text("Apply compare value", bundle: .module)
                    } icon: {
                        Image(systemName: "return")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
            }
            .rowEditColor()
        }
        .rowEditColor(backgroundColor: .blue)
        .frame(width: valueFor(iOS: 265, macOS: 265, tvOS: 265, visionOS: 325))
        .onChange(of: root.gameController.gameItem(for: itemId).compareValue, initial: true) {
            value = String("\(Int(root.gameController.gameItem(for: itemId).compareValue))")
        }
        .onAppear {
#if os(iOS) || os(macOS)
            isFocused = true
#endif
        }
    }

    private var rowMinusButtonsView: some View {
        HStack {
            ForEach([10, 5, 2, 1], id: \.self) { value in
                QuickEditorButtonView(number: valueIntBinding, value: value, title: "\(value)", isAddition: false)
            }
        }
    }

    private var rowPlusButtonsView: some View {
        HStack {
            ForEach([1, 2, 5, 10], id: \.self) { value in
                QuickEditorButtonView(number: valueIntBinding, value: value, title: "\(value)", isAddition: true)
            }
        }
    }
}
