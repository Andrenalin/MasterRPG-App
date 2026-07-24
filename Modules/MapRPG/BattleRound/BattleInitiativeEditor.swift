// @copyright André Trettin

import Foundation
import SwiftUI

struct BattleInitiativeEditor: View {
    let combatantId: UUID
    let value: Int?
    let setValue: @MainActor (UUID, Int?) -> Void
    let adjust: @MainActor (UUID, Int) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button("Decrease Initiative", systemImage: "minus", action: decrease)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)

            TextField("Initiative", text: $text)
                .battleInitiativeTextFieldStyle()
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 64)
                .focused($isFocused)
                .battleNumberKeyboard()
                .onSubmit(commit)

            Button("Increase Initiative", systemImage: "plus", action: increase)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .onChange(of: value, initial: true) { _, newValue in
            guard !isFocused else { return }
            let newText = newValue.map(String.init) ?? ""
            if text != newText {
                text = newText
            }
        }
        .onChange(of: isFocused) { oldValue, newValue in
            guard oldValue && !newValue else { return }
            commit()
        }
        .accessibilityElement(children: .contain)
    }

    private func decrease() {
        commit()
        adjust(combatantId, -1)
    }

    private func increase() {
        commit()
        adjust(combatantId, 1)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = trimmed.isEmpty ? nil : Int(trimmed)
        guard parsed != value else { return }
        setValue(combatantId, parsed)
    }
}

#Preview("Initiative editor") {
    @Previewable @State var initiative: Int? = 18
    let combatantID = UUID()

    BattleInitiativeEditor(
        combatantId: combatantID,
        value: initiative,
        setValue: { _, value in initiative = value },
        adjust: { _, amount in initiative = (initiative ?? 0) + amount }
    )
    .padding()
}
