// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

@MainActor @Observable
final class BattleRoundCardState {
    var characterSheet: BattleCharacterSheetPresentation?

    func openCharacter(
        _ combatant: BattleCombatant,
        controller: BattleRoundController,
        showCharacter: @MainActor (BattleCombatant) -> Void
    ) {
        if let sheet = BattleCharacterSheetFactory(characterRoot: controller.root.characterRoot).presentation(for: combatant) {
            characterSheet = characterSheet?.id == sheet.id ? nil : sheet
        } else {
            showCharacter(combatant)
        }
    }
}

/// The properties `BattleRoundWideCardLayout` and `BattleRoundCompactCardLayout`
/// both need, bundled into one struct so a future added field only needs
/// declaring once instead of twice — the two layouts' own `body` arrangements
/// remain genuinely different and stay separate types. See CODE_AUDIT §9.9.
struct BattleRoundCardLayoutContext {
    let state: BattleRoundCardState
    let presentation: BattleRoundCardPresentation
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void
}

extension BattleCombatant {
    var hasCharacter: Bool { gameCharacterId != nil || sourceCharacterId != nil }
}

struct BattleRoundCard: View {
    let presentation: BattleRoundCardPresentation
    let controller: BattleRoundController
    let cardLayout: BattleRoundCardLayout
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var cardState = BattleRoundCardState()

    var body: some View {
        // A single wrapping container keeps this a unary view: the card
        // content and the optional inline character sheet must always
        // reconcile as one row, or `BattleRoundList`'s `.frame(maxWidth:
        // .infinity)` / `.transition` / `.draggable` fan out across whichever
        // children happen to exist at that moment instead of bounding one
        // stable row — visible as rows resizing/losing full width whenever
        // `cardState.characterSheet` is cleared (e.g. switching attacker).
        let layoutContext = BattleRoundCardLayoutContext(
            state: cardState,
            presentation: presentation,
            controller: controller,
            showCharacter: showCharacter,
            selectHitPoints: selectHitPoints,
            selectInitiative: selectInitiative
        )
        VStack(spacing: 0) {
            Group {
                switch cardLayout {
                case .wide:
                    BattleRoundWideCardLayout(context: layoutContext)
                case .compact:
                    BattleRoundCompactCardLayout(context: layoutContext)
                }
            }
            .padding(10)
            #if !os(visionOS)
            .glassEffect(
                presentation.isActive
                    ? .regular.tint(.blue)
                    : .regular,
                in: .rect(cornerRadius: 12)
            )
            #endif
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 12
                )
                .fill(presentation.isActive ? Color.blue : .clear)
                .frame(width: 4)
                .accessibilityHidden(true)
            }
            // "Dead" dimming is owned solely by `BattleParticipantColumn`
            // (both the attacker and every defender dim themselves the same
            // way) — deliberately not repeated here. It used to also be
            // applied at this card level for the attacker only, which
            // compounded with the column's own dimming and made a dead
            // attacker's row read far darker than a dead defender's. See
            // CODE_AUDIT §8.1.
            .animation(
                accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
                value: presentation.isActive
            )
            .accessibilityElement(children: .contain)
            .onChange(of: presentation.isActive) { wasActive, isActive in
                // A turn moving on should never leave a stale character sheet
                // open on the card that was just active.
                guard wasActive, !isActive else { return }
                cardState.characterSheet = nil
            }
            .contextMenu {
                BattleRoundParticipantActionsMenu(
                    role: .attacker,
                    presentation: presentation.attacker,
                    cardState: cardState,
                    controller: controller,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints
                )
                ForEach(presentation.defenders) { defender in
                    BattleRoundParticipantActionsMenu(
                        role: .defender,
                        presentation: defender,
                        cardState: cardState,
                        controller: controller,
                        showCharacter: showCharacter,
                        selectHitPoints: selectHitPoints
                    )
                }
            }

            if let sheet = cardState.characterSheet {
                SheetRootView(root: sheet.root, rootModel: sheet.sheet)
            }
        }
    }
}

extension BattleRoundCard: Equatable {
    /// Re-rendered on every live Battle Round tick (HP, initiative, active turn,
    /// rolls) for every card in the turn order — comparing only what actually
    /// changes the rendered output lets `.equatable()` skip re-diffing cards
    /// whose own data is unchanged. The three action closures are intentionally
    /// excluded: they're never `Equatable`, and — once hoisted to stable method
    /// references at the call site (see `BattleRoundView`) — always behave the
    /// same regardless of which render's instance gets kept.
    ///
    /// `cardLayout` must be a plain stored property, not `@Environment`:
    /// `.equatable()` invokes this `==` on struct copies that were never
    /// installed into the view tree, and reading an `@Environment`-wrapped
    /// property outside that installation always silently returns its
    /// default value (with a runtime diagnostic) instead of the real one.
    ///
    /// `accessibilityReduceMotion` (also `@Environment`) is deliberately left
    /// out of this comparison for the same reason — comparing it here would
    /// just compare the environment default against itself, not the real
    /// setting. The accepted tradeoff: toggling Reduce Motion while a card's
    /// other compared state is unchanged may leave its `.animation` modifier
    /// at whatever it captured on the last real re-render, until an
    /// unrelated field change forces one. See CODE_AUDIT §8.2.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.presentation == rhs.presentation
            && lhs.controller.root === rhs.controller.root
            && lhs.cardLayout == rhs.cardLayout
    }
}

#Preview("Battle card", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleRoundCard(
            presentation: card,
            controller: controller,
            cardLayout: .wide,
            showCharacter: { _ in },
            selectHitPoints: { _ in },
            selectInitiative: { _ in }
        )
        .padding()
        .environment(AppFocusModel())
    }
}
