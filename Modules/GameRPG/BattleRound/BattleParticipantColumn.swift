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
    let cardLayout: BattleRoundCardLayout
    let isActive: Bool
    let tint: Color
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void

    private var root: MapRootModel { controller.root.mapRoot }

    /// `48pt` square avatar — written once here and reused below instead of
    /// repeating the literal at both the requested image size and the
    /// displayed frame. See CODE_AUDIT §9.5.
    private static let avatarSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: BattleRoundSpacing.tight) {
            BattleParticipantNameRow(
                combatant: combatant,
                role: role,
                cardLayout: cardLayout,
                toggleDead: toggleDead
            )

            HStack(alignment: .center, spacing: BattleRoundSpacing.standard) {
                Button(action: openCharacter) {
                    controller.root.photoRoot.viewController.mapImage(
                        root: controller.root.photoRoot,
                        for: combatant.photoId,
                        size: CGSize(width: Self.avatarSize, height: Self.avatarSize),
                        color: combatant.color
                    )
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .clipShape(.circle)
                    .overlay {
                        if combatant.isDead {
                            Circle()
                                .fill(.black.opacity(0.54))
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
                .battleLinkCharacterDropDestination { characters, _ in
                    guard let character = characters.first else { return false }
                    return controller.assignCharacter(combatant.id, character.itemId)
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
                        .contentShape(.rect)
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
                    // benefit. See CODE_AUDIT §7.1.
                    let hp = hitPointsValue
                    HStack(spacing: BattleRoundSpacing.tight) {
                        HStack(spacing: BattleRoundSpacing.extraTight) {
                            Text("HP:", bundle: .module)
                            Text(verbatim: hp ?? "")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .contentShape(.rect)
                        .foregroundStyle(hp == nil ? .tertiary : .primary)
#if os(iOS) || os(macOS) || os(visionOS)
                        .battleLinkCharacterDropDestination(action: valueDropAction(kind: .hitPoints))
#endif
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

                // Only the compact card's attacker owns the whole row.
                BattleRollResults(
                    results: presentation.rolls,
                    tint: tint,
                    fillsRow: cardLayout == .compact && role == .attacker
                )
            }
        }
        .opacity(combatant.isDead ? 0.62 : 1)
    }

    private var combatant: BattleCombatant { presentation.combatant }

    private var haloColor: Color {
        if presentation.isRollRecipient || isActive { return tint }
        return .gray.opacity(0.45)
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

    private func openCharacter() {
        state.openCharacter(combatant, controller: controller, showCharacter: showCharacter)
    }

    private func selectRollRecipient() {
        controller.selectRollRecipient(combatant.id)
    }

    private func toggleDead() {
        controller.setDead(combatant.id, !combatant.isDead)
    }

    /// Shared by the Initiative and Hit Points drop targets below — the two
    /// were byte-identical apart from `kind`. See CODE_AUDIT §9.3.
    private func valueDropAction(kind: BattleValueKind) -> @MainActor ([LinkCharacterData], CGPoint) -> Bool {
        { values, _ in
            guard let value = values.first, let entryId = value.entryId else {
                return false
            }
            // `assignValueEntry` resolves `value.itemId` up through any
            // value-group ownership chain and rejects it unless that
            // resolves to this combatant's own source Character.
            return controller.assignValueEntry(
                combatantId: combatant.id,
                sourceCharacterId: value.itemId,
                sourceEntryId: entryId,
                kind: kind
            )
        }
    }
}

extension BattleParticipantColumn: Equatable {
    /// Mirrors `BattleRoundCard`'s own `Equatable` one level down — a card's
    /// equatable-skip is at whole-card granularity, so any single
    /// defender's HP/roll changing used to force re-diffing every sibling
    /// defender and the attacker column too, even though only one
    /// participant's own data actually changed. See CODE_AUDIT §8.3. The
    /// `showCharacter` closure is excluded for the same reason
    /// `BattleRoundCard` excludes its own: never `Equatable`, and stable
    /// once hoisted to a method reference at the call site (see
    /// `BattleRoundView`).
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state === rhs.state
            && lhs.presentation == rhs.presentation
            && lhs.role == rhs.role
            && lhs.cardLayout == rhs.cardLayout
            && lhs.isActive == rhs.isActive
            && lhs.tint == rhs.tint
            && lhs.controller.root === rhs.controller.root
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
                cardLayout: .wide,
                isActive: true,
                tint: .red,
                controller: controller,
                showCharacter: { _ in }
            )
            .padding()
        }
    }
}
