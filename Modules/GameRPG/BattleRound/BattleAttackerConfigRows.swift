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

    var needsValueConfiguration: Bool {
        needsInitiativeConfiguration || needsHitPointsConfiguration
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
    let cardLayout: BattleRoundCardLayout
    let state: BattleRoundCardState
    let controller: BattleRoundController
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

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
                        cardLayout: cardLayout,
                        state: state,
                        controller: controller,
                        select: selectInitiative
                    )
                }
                if showsHitPoints {
                    BattleValueConfigRow(
                        kind: .hitPoints,
                        combatant: combatant,
                        cardLayout: cardLayout,
                        state: state,
                        controller: controller,
                        select: selectHitPoints
                    )
                }
            }
            // The compact card gives the rows its full width. The wide card
            // is sized by its content, so the rows keep their natural width
            // instead of pulling the card to the window's width.
            .fixedSize(horizontal: cardLayout == .wide, vertical: false)
        }
    }
}

/// One grid row: `Ini: − [value] + pick ✓` (and the same for HP).
private struct BattleValueConfigRow: View {
    let kind: BattleValueKind
    let combatant: BattleCombatant
    let cardLayout: BattleRoundCardLayout
    let state: BattleRoundCardState
    let controller: BattleRoundController
    let select: @MainActor (BattleCombatant) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    // Wide card only: room for a few digits. The compact card lets the field
    // fill the row.
    @ScaledMetric(relativeTo: .body) private var wideFieldWidth: CGFloat = 72

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
                // No placeholder in the wide card: its short field would
                // only show a truncated one.
                TextField(
                    kind.fieldTitle,
                    text: $text,
                    prompt: cardLayout == .wide ? Text(verbatim: "") : nil
                )
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: cardLayout == .wide ? wideFieldWidth : nil)
                .focused($isFocused)
                .onSubmit(commit)
                .submitLabel(.done)
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
                text = value.map(String.init) ?? ""
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
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            text = currentValue.map(String.init) ?? ""
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
        .foregroundStyle(.secondary)
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
                cardLayout: .compact,
                state: BattleRoundCardState(),
                controller: controller,
                selectHitPoints: { _ in },
                selectInitiative: { _ in }
            )
        }
        .frame(width: 340)
        .padding()
    }
}
