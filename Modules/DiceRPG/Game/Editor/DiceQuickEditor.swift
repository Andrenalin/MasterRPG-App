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
    @Environment(\.appTheme) private var theme

    @State private var value: String = ""
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = {
#if os(tvOS)
        420
#elseif os(visionOS)
        325
#else
        300
#endif
    }()

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
            .themedWell()

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
                .buttonStyle(ThemedQuickStepButtonStyle())
                .fixedSize()
                .disabled(compareValue == nil)
                .opacity(compareValue == nil ? 0.5 : 1)
            }
            .themedWell()
        }
        .padding(6)
        .foregroundStyle(theme.foregroundColor)
        .tint(theme.accentColor)
        .background(theme.panelColor, in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ResolvedAppTheme.panelCornerRadius)
                .strokeBorder(theme.accentColor, lineWidth: 2)
        }
        .frame(width: width)
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
                QuickEditorButtonView(number: numberBinding, value: value, title: "\(value)", isAddition: isAddition, isThemed: true)
            }
        }
    }
}

/// The inset well inside the editor panel: the theme canvas under the theme foreground.
private extension View {
    func themedWell() -> some View {
        modifier(DiceQuickEditorWellModifier())
    }
}

private struct DiceQuickEditorWellModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(theme.foregroundColor)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.canvas.color, in: .rect(cornerRadius: ResolvedAppTheme.elementCornerRadius))
    }
}
