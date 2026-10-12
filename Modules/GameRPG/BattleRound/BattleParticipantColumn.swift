// @copyright André Trettin

import CharacterRPG
import CoreRPG
import MapRPG
import PhotoRPG
import SwiftUI

enum BattleRoundParticipantRole {
    case attacker
    case defender
}

struct BattleParticipantColumn: View {
    let state: BattleRoundCardState
    let presentation: BattleRoundParticipantPresentation
    let role: BattleRoundParticipantRole
    let isActive: Bool
    let tint: Color
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    /// The square avatar's side — one value for both the requested image size
    /// and the displayed frame. Scales with Dynamic Type like the text next
    /// to it.
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 48
    /// The least width of the "Ini:" / "HP:" labels, so an empty one is still
    /// a target a value can be dropped on.
    @ScaledMetric(relativeTo: .caption2) private var valueLabelMinWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: BattleRoundSpacing.tight) {
            BattleParticipantNameRow(
                combatant: combatant,
                role: role,
                toggleDead: toggleDead
            )

            HStack(alignment: .center, spacing: BattleRoundSpacing.standard) {
                Button(action: openCharacter) {
                    controller.root.photoRoot.viewController.mapImage(
                        root: controller.root.photoRoot,
                        for: combatant.photoId,
                        size: CGSize(width: avatarSize, height: avatarSize),
                        color: combatant.color
                    )
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(.circle)
                    .overlay {
                        if combatant.isDead {
                            Color.black.opacity(0.54)
                                .clipShape(.circle)
                            Image(systemName: "xmark")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        } else if !hasCharacter {
                            Image(systemName: "person.badge.plus")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, combatant.color)
                                .padding(3)
                                .background(.black.opacity(0.55), in: .circle)
                        }
                    }
                    .overlay {
                        // A stroked shape is a view of its own, so there is no
                        // static-member (`.circle`) spelling for it.
                        Circle()
                            .strokeBorder(haloColor, lineWidth: haloWidth)
                    }
                    .shadow(
                        color: isActive ? tint.opacity(0.5) : .black.opacity(0.2),
                        radius: isActive ? 6 : 2,
                        y: 2
                    )
                }
                .buttonStyle(.plain)
                .help(
                    Text(
                        hasCharacter ? "Open character sheet" : "Choose a Character",
                        bundle: .module
                    )
                )
                .accessibilityLabel(
                    hasCharacter
                    ? Text("Open character sheet for \(combatant.name)", bundle: .module)
                    : Text("Choose a Character for \(combatant.name)", bundle: .module)
                )
                .accessibilityValue(avatarAccessibilityValue)
#if os(iOS) || os(macOS) || os(visionOS)
                .battleLinkCharacterDropDestination(outline: .circle) { characters, _ in
                    guard let character = characters.first else { return false }
                    return screenModel.assignDroppedCharacter(
                        character,
                        to: combatant.id,
                        controller: controller
                    )
                }
#endif
                
                VStack(alignment: .leading, spacing: BattleRoundSpacing.compact) {
                    HStack(spacing: BattleRoundSpacing.tight) {
                        // Not tappable: the attacker's config row picks or
                        // types the value. A value can still be dropped here.
                        HStack(spacing: BattleRoundSpacing.extraTight) {
                            Text("Ini:", bundle: .module)
                            Text(verbatim: initiativeValue ?? "")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .battleValueDropLabel(minWidth: valueLabelMinWidth)
                        .foregroundStyle(initiativeValue == nil ? .tertiary : .primary)
#if os(iOS) || os(macOS) || os(visionOS)
                        .battleLinkCharacterDropDestination(action: valueDropAction(kind: .initiative))
#endif
                        if canRevealValueRow(.initiative) {
                            BattleValueRowRevealButton(kind: .initiative, state: state)
                        }
                    }

                    // Computed once and reused below: `hitPointsValue` walks a
                    // linked entry's formula chain, so reading it a second time
                    // purely for the color check would redo that work for no
                    // benefit.
                    let hp = hitPointsValue
                    HStack(spacing: BattleRoundSpacing.tight) {
                        HStack(spacing: BattleRoundSpacing.extraTight) {
                            Text("HP:", bundle: .module)
                            Text(verbatim: hp ?? "")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .battleValueDropLabel(minWidth: valueLabelMinWidth)
                        .foregroundStyle(hp == nil ? .tertiary : .primary)
#if os(iOS) || os(macOS) || os(visionOS)
                        .battleLinkCharacterDropDestination(action: valueDropAction(kind: .hitPoints))
#endif
                        if hitPointsCannotBeCalculated {
                            BattleHitPointsWarning()
                        }
                        if canRevealValueRow(.hitPoints) {
                            BattleValueRowRevealButton(kind: .hitPoints, state: state)
                        }
                    }
                }
            }

            HStack(spacing: BattleRoundSpacing.compact) {
                if presentation.canReceiveRoll {
                    Button(action: selectRollRecipient) {
                        Label {
                            Text("Roll Target", bundle: .module)
                        } icon: {
                            Image(
                                systemName: presentation.isRollRecipient
                                    ? "dice.fill"
                                    : "dice"
                            )
                        }
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(presentation.isRollRecipient ? tint : .secondary)
                    .help(Text("Assign the next master roll to this combatant", bundle: .module))
                    .accessibilityValue(
                        Text(
                            presentation.isRollRecipient ? "Selected" : "Not selected",
                            bundle: .module
                        )
                    )
                }

                // Only the attacker owns the whole row.
                BattleRollResults(
                    results: presentation.rolls,
                    tint: tint,
                    fillsRow: role == .attacker
                )
            }
        }
        .opacity(combatant.isDead ? 0.62 : 1)
    }

    private var combatant: BattleCombatant { presentation.combatant }

    private var haloColor: Color {
        if presentation.isRollRecipient || isActive { return tint }
        return BattleRoundPalette.inactive.opacity(0.45)
    }

    private var haloWidth: CGFloat {
        presentation.isRollRecipient || isActive ? 3 : 1
    }

    /// The avatar halo color is the only signal for "active turn"/"roll
    /// recipient" — mirrors the same state as `haloColor`/`haloWidth` in text
    /// so VoiceOver users (and color-blind sighted users) aren't left without
    /// it.
    private var avatarAccessibilityValue: Text {
        switch (isActive, presentation.isRollRecipient) {
        case (true, true):
            Text("Active turn, selected roll target", bundle: .module)
        case (true, false):
            Text("Active turn", bundle: .module)
        case (false, true):
            Text("Selected roll target", bundle: .module)
        case (false, false):
            Text("Not active", bundle: .module)
        }
    }

    private var hasCharacter: Bool { combatant.hasCharacter }

    /// Only the attacker has config rows; the button reopens one that is
    /// currently hidden.
    private func canRevealValueRow(_ kind: BattleValueKind) -> Bool {
        role == .attacker && hasCharacter && !state.showsValueRow(kind, for: combatant)
    }

    private var hitPointsValue: String? {
        guard let characterId = combatant.gameCharacterId,
              let entryId = combatant.hitPointsEntryId else {
            return nil
        }
        return controller.root.characterRoot.valueGameControllable.gameEntryDisplayValue(
            characterId: characterId,
            entryId: entryId
        )
    }

    private var initiativeValue: String? {
        combatant.initiative.map(String.init)
    }

    /// A hit-points entry is chosen, but no health comes out of it: its base
    /// is free text or a formula that does not evaluate. Without a mark the
    /// only sign is a gray health ring on the map.
    private var hitPointsCannotBeCalculated: Bool {
        combatant.hitPointsEntryId != nil && combatant.pin.healthPercent == nil
    }

    private func openCharacter() {
        state.openCharacter(combatant, controller: controller, screenModel: screenModel)
    }

    private func selectRollRecipient() {
        controller.selectRollRecipient(combatant.id)
    }

    private func toggleDead() {
        controller.setDead(combatant.id, !combatant.isDead)
    }

    /// Shared by the Initiative and Hit Points drop targets — the two differ
    /// only in `kind`. Goes through the screen model, so a pending "choose
    /// this value" flow for the combatant ends with the drop.
    private func valueDropAction(kind: BattleValueKind) -> @MainActor ([LinkCharacterData], CGPoint) -> Bool {
        { values, _ in
            guard let value = values.first else { return false }
            return screenModel.assignDroppedValue(
                value,
                to: combatant.id,
                kind: kind,
                controller: controller
            )
        }
    }
}

/// Marks a hit-points entry that yields no health, next to "HP:".
private struct BattleHitPointsWarning: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .imageScale(.small)
            .foregroundStyle(.orange)
            .help(Text("Hit points cannot be calculated from the chosen value.", bundle: .module))
            .accessibilityLabel(Text("Hit points cannot be calculated from the chosen value.", bundle: .module))
    }
}

private extension View {
    /// Gives the caption-sized "Ini:" / "HP:" label a drop target of usable
    /// size: some padding, a least width, and the whole area hit-testable.
    func battleValueDropLabel(minWidth: CGFloat) -> some View {
        frame(minWidth: minWidth, alignment: .leading)
            .padding(.vertical, BattleRoundSpacing.extraTight)
            .padding(.horizontal, BattleRoundSpacing.tight)
            .contentShape(.rect)
    }
}

extension BattleParticipantColumn: Equatable {
    /// Mirrors `BattleRoundCard`'s own `Equatable` one level down — a card's
    /// equatable-skip is at whole-card granularity, so any single
    /// defender's HP/roll changing used to force re-diffing every sibling
    /// defender and the attacker column too, even though only one
    /// participant's own data actually changed.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state === rhs.state
            && lhs.presentation == rhs.presentation
            && lhs.role == rhs.role
            && lhs.isActive == rhs.isActive
            && lhs.tint == rhs.tint
            && lhs.controller.root === rhs.controller.root
            && lhs.screenModel === rhs.screenModel
    }
}

#Preview("Battle participant", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    VStack {
        if let participant = model.cardPresentations.first?.defenders.first {
            BattleParticipantColumn(
                state: BattleRoundCardState(),
                presentation: participant,
                role: .defender,
                isActive: true,
                tint: BattleRoundPalette.defender,
                controller: controller,
                screenModel: BattleRoundScreenModel(model: model)
            )
            .padding()
        }
    }
}
