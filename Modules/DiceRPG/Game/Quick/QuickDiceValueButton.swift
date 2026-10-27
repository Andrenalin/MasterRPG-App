// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The value of a quick dice slot's dice and, on tap, the compare-value quick editor. The slot
/// owns what a new value means, so the editor reports it instead of changing the dice itself.
struct QuickDiceValueButton: View {
    let diceId: UUID
    let onValueChange: (Int) -> Void

    @Environment(DiceRootModel.self) private var root

    @State private var isEditorShown = false

    var body: some View {
        let dice = root.gameController.gameItem(for: diceId)
        if dice.compareOption != .off || dice.addDiceEvery > 0 {
            // The result is worked out once per update; the icon and the tint both follow it.
            let outcome = root.gameController.hasResults(itemId: diceId) ? root.gameController.result(itemId: diceId).checked : nil
            Button {
                isEditorShown = true
            } label: {
                // Narrow slots drop the icon and keep the number.
                ViewThatFits(in: .horizontal) {
                    valueLabel(dice, outcome: outcome)
                        .labelStyle(.titleAndIcon)
                    valueLabel(dice, outcome: outcome)
                        .labelStyle(.titleOnly)
                }
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                // Keeps the compact size but hit-tests at least 44×44 pt (HIG).
                .minimumHitArea()
            }
            .accessibilityLabel(Text("Change compare value", bundle: .module))
            .accessibilityValue(Text(dice.compareValue.saturatingInt, format: .number))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(outcome.map { $0 ? Color.green : Color.red })
            .modifier(QuickDiceEditorPresentation(isPresented: $isEditorShown) {
                DiceQuickEditor(itemId: diceId) { newValue in
                    onValueChange(newValue)
                    isEditorShown = false
                }
                .environment(root)
            })
        }
    }

    private func valueLabel(_ dice: DiceModel, outcome: Bool?) -> some View {
        Label {
            Text(dice.compareValue.saturatingInt, format: .number)
        } icon: {
            Image(systemName: icon(outcome: outcome))
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
    }

    private func icon(outcome: Bool?) -> String {
        guard let outcome else { return "slider.horizontal.3" }
        return outcome ? "checkmark" : "xmark"
    }
}

/// A popover where there is one; tvOS has none.
private struct QuickDiceEditorPresentation<Editor: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let editor: () -> Editor

    func body(content: Content) -> some View {
#if os(tvOS)
        content.sheet(isPresented: $isPresented, content: editor)
#else
        content.popover(isPresented: $isPresented) {
            editor()
                .padding()
                .presentationCompactAdaptation(.popover)
        }
#endif
    }
}

#Preview(traits: .mockData) {
    QuickDiceValueButton(diceId: DiceModel.previewId) { _ in }
        .environment(DiceRootModel.preview)
}
