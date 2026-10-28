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

    /// The typed value, or `nil` while it is not one a dice takes (empty, 0 or less), so Apply
    /// stays disabled instead of closing with no change. See CODE_AUDIT_Since_3.0.1 §5.12.
    private var compareValue: Int? {
        Int(value).flatMap { $0 > 0 ? $0 : nil }
    }

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
                DiceQuickEditorRowButtonsView(numberBinding: valueIntBinding, values: [10, 5, 2, 1], isAddition: false)
                DiceQuickEditorRowButtonsView(numberBinding: valueIntBinding, values: [1, 2, 5, 10], isAddition: true)
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
                    guard let compareValue else { return }
                    Task {
                        await action(compareValue)
                    }
                }

                Button {
                    guard let compareValue else { return }
                    Task {
                        await action(compareValue)
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
                .disabled(compareValue == nil)
                .frame(minWidth: 44, minHeight: 44)
            }
            .rowEditColor()
        }
        .rowEditColor(backgroundColor: .blue)
        .frame(width: valueFor(iOS: 265, macOS: 265, tvOS: 265, visionOS: 325))
        .onChange(of: root.gameController.gameItem(for: itemId).compareValue, initial: true) {
            value = String("\(root.gameController.gameItem(for: itemId).compareValue.saturatingInt)")
        }
        .onAppear {
#if os(iOS) || os(macOS)
            isFocused = true
#endif
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

// The minus/plus rows were previously two near-identical views differing
// only in their value order and `isAddition`. See CODE_AUDIT §9.16.
private struct DiceQuickEditorRowButtonsView: View {
    let numberBinding: Binding<Int>
    let values: [Int]
    let isAddition: Bool

    var body: some View {
        HStack {
            ForEach(values, id: \.self) { value in
                QuickEditorButtonView(number: numberBinding, value: value, title: "\(value)", isAddition: isAddition)
            }
        }
    }
}
