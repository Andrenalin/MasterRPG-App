// @copyright André Trettin

import MapRPG
import SwiftUI

extension BattleCombatant {
    /// A Character is assigned, but its Initiative entry was not found or it
    /// has no usable value yet.
    var needsInitiativeConfiguration: Bool {
        hasCharacter && (initiativeEntryId == nil || initiative == nil)
    }

    /// A Character is assigned, but its Hit Points entry was not found.
    var needsHitPointsConfiguration: Bool {
        hasCharacter && hitPointsEntryId == nil
    }

    func needsConfiguration(_ kind: BattleValueKind) -> Bool {
        switch kind {
        case .initiative: needsInitiativeConfiguration
        case .hitPoints: needsHitPointsConfiguration
        }
    }
}

/// Full-width rows under an attacker for typing or picking its Initiative and
/// Hit Points. A row opens by itself while its value is missing and stays
/// until the game master confirms it; the participant column can reopen it.
struct BattleAttackerConfigRows: View {
    let combatant: BattleCombatant
    let state: BattleRoundCardState
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some View {
        let showsInitiative = state.showsValueRow(.initiative, for: combatant)
        let showsHitPoints = state.showsValueRow(.hitPoints, for: combatant)
        // No container at all when both are hidden, so the card's stack
        // doesn't space around an empty row.
        if showsInitiative || showsHitPoints {
            // A grid, so label, value, pick and confirm line up across both rows.
            Grid(
                alignment: .leading,
                horizontalSpacing: BattleRoundSpacing.standard,
                verticalSpacing: BattleRoundSpacing.standard
            ) {
                if showsInitiative {
                    BattleValueConfigRow(
                        kind: .initiative,
                        combatant: combatant,
                        state: state,
                        controller: controller,
                        select: screenModel.selectInitiative
                    )
                }
                if showsHitPoints {
                    BattleValueConfigRow(
                        kind: .hitPoints,
                        combatant: combatant,
                        state: state,
                        controller: controller,
                        select: screenModel.selectHitPoints
                    )
                }
            }
        }
    }
}

/// One grid row: `Ini: − [value] + pick ✓` (and the same for HP).
private struct BattleValueConfigRow: View {
    let kind: BattleValueKind
    let combatant: BattleCombatant
    let state: BattleRoundCardState
    let controller: BattleRoundController
    let select: @MainActor (BattleCombatant) -> Void

    @Environment(\.locale) private var locale
    @State private var text = ""
    /// What was typed is not a whole number. The text stays in the field,
    /// marked, instead of silently turning back into the previous value.
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let value = currentValue
        GridRow {
            Text(kind.shortLabel)
                .font(.caption)

            HStack(spacing: 0) {
                BattleConfigIconButton(title: kind.decreaseTitle, systemImage: "minus") {
                    adjust(by: -1)
                }

                // Committed on submit or when focus leaves, not per keystroke:
                // a new initiative re-sorts the turn order.
                TextField(kind.fieldTitle, text: $text)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isInvalid ? Color.red : Color.primary)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .submitLabel(.done)
                    .help(isInvalid ? Text("Not a whole number", bundle: .module) : Text(kind.fieldTitle))
                    .accessibilityValue(
                        isInvalid ? Text("Not a whole number", bundle: .module) : Text(verbatim: text)
                    )
#if !os(macOS)
                    .keyboardType(.numbersAndPunctuation)
#endif
#if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
#endif

                BattleConfigIconButton(title: kind.increaseTitle, systemImage: "plus") {
                    adjust(by: 1)
                }
            }
            .disabled(!isEditable)
            .onChange(of: value, initial: true) { _, value in
                text = BattleNumberInput.text(for: value, locale: locale)
                isInvalid = false
            }
            .onChange(of: text) {
                // Typing again clears the mark; the next commit decides anew.
                isInvalid = false
            }
            .onChange(of: isFocused) { _, isFocused in
                guard !isFocused else { return }
                commit()
            }
            .onAppear {
                // Opened for a missing value: stay open once it gets set,
                // until the game master confirms with the checkmark.
                state.setValueRow(kind, isShown: true)
            }

            BattleConfigIconButton(title: kind.chooseTitle, systemImage: kind.chooseSystemImage) {
                select(combatant)
            }

            if value != nil {
                BattleConfigIconButton(
                    title: String(localized: "Done", bundle: .module),
                    systemImage: "checkmark"
                ) {
                    state.setValueRow(kind, isShown: false)
                }
            }
        }
    }

    private var currentValue: Int? {
        switch kind {
        case .initiative: combatant.initiative
        case .hitPoints: controller.hitPoints(for: combatant)
        }
    }

    /// Initiative is a battle value and always editable. Hit points live in
    /// the Character's entry, so there is nothing to write before one is
    /// chosen.
    private var isEditable: Bool {
        switch kind {
        case .initiative: true
        case .hitPoints: currentValue != nil
        }
    }

    private func adjust(by amount: Int) {
        switch kind {
        case .initiative: controller.adjustInitiative(combatant.id, amount)
        case .hitPoints: controller.adjustHitPoints(combatant.id, amount)
        }
    }

    private func commit() {
        // An emptied field goes back to the current value. Anything else that
        // is not a whole number stays visible and is marked: the locale's own
        // digits, grouping separators and minus sign all parse.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            text = BattleNumberInput.text(for: currentValue, locale: locale)
            return
        }
        guard let value = BattleNumberInput.parse(text, locale: locale) else {
            isInvalid = true
            return
        }
        switch kind {
        case .initiative: controller.setInitiative(combatant.id, value)
        case .hitPoints: controller.setHitPoints(combatant.id, value)
        }
    }
}

/// One square icon button; every button of a config row uses it so they all
/// come out the same size.
private struct BattleConfigIconButton: View {
    let title: String
    let systemImage: String
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: side, height: side)
        }
        .buttonStyle(.bordered)
        .help(Text(title))
    }
}

extension BattleValueKind {
    var shortLabel: String {
        switch self {
        case .initiative: String(localized: "Ini:", bundle: .module)
        case .hitPoints: String(localized: "HP:", bundle: .module)
        }
    }

    var fieldTitle: String {
        switch self {
        case .initiative: String(localized: "Initiative", bundle: .module)
        case .hitPoints: String(localized: "Hit Points", bundle: .module)
        }
    }

    var decreaseTitle: String {
        switch self {
        case .initiative: String(localized: "Decrease Initiative", bundle: .module)
        case .hitPoints: String(localized: "Decrease Hit Points", bundle: .module)
        }
    }

    var increaseTitle: String {
        switch self {
        case .initiative: String(localized: "Increase Initiative", bundle: .module)
        case .hitPoints: String(localized: "Increase Hit Points", bundle: .module)
        }
    }

    var chooseTitle: String {
        switch self {
        case .initiative: String(localized: "Choose the Initiative value", bundle: .module)
        case .hitPoints: String(localized: "Choose the Hit Points value", bundle: .module)
        }
    }

    var chooseSystemImage: String {
        switch self {
        case .initiative: "person.crop.circle.badge.checkmark"
        case .hitPoints: "heart.text.square"
        }
    }

    var configureTitle: String {
        switch self {
        case .initiative: String(localized: "Configure Initiative", bundle: .module)
        case .hitPoints: String(localized: "Configure Hit Points", bundle: .module)
        }
    }
}

/// Reopens a config row from the participant column's "Ini:" / "HP:" line.
struct BattleValueRowRevealButton: View {
    let kind: BattleValueKind
    let state: BattleRoundCardState

    var body: some View {
        Button(kind.configureTitle, systemImage: "gearshape") {
            state.setValueRow(kind, isShown: true)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .imageScale(.small)
        .help(Text(kind.configureTitle))
    }
}

#Preview("Attacker config rows", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        VStack {
            BattleAttackerConfigRows(
                combatant: card.attacker.combatant,
                state: BattleRoundCardState(),
                controller: controller,
                screenModel: BattleRoundScreenModel(model: model)
            )
        }
        .frame(width: 340)
        .padding()
    }
}
