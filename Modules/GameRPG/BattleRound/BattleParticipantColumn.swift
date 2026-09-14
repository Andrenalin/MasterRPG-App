// @copyright André Trettin

import CharacterRPG
import CoreRPG
import MapRPG
import PhotoRPG
import SwiftUI

struct BattleParticipantColumn: View {
    let state: BattleRoundCardState
    let presentation: BattleRoundParticipantPresentation
    let isActive: Bool
    let tint: Color
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

    private var root: MapRootModel { controller.root.mapRoot }

    /// `48pt` square avatar — written once here and reused below instead of
    /// repeating the literal at both the requested image size and the
    /// displayed frame. See CODE_AUDIT §9.5.
    private static let avatarSize: CGFloat = 48

    // A hard-coded `maxWidth` ignored Dynamic Type entirely, risking illegible
    // truncation of a free-text combatant name at larger accessibility sizes.
    @ScaledMetric(relativeTo: .caption2) private var nameMaxWidth: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: BattleRoundSpacing.tight) {
            HStack(spacing: BattleRoundSpacing.extraTight) {
                Button(
                    combatant.isDead ? "Mark Alive" : "Mark Dead",
                    systemImage: combatant.isDead ? "heart.fill" : "figure.fall",
                    action: toggleDead
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(combatant.isDead ? .green : .red)
                .help(
                    Text(
                        combatant.isDead ? "Mark Alive" : "Mark Dead",
                        bundle: .module
                    )
                )
                
                Text(combatant.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: nameMaxWidth)
                    .help(Text(verbatim: combatant.name))
            }
            
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
                    Button(action: selectInitiativeEntry) {
                        HStack(spacing: BattleRoundSpacing.extraTight) {
                            Text("Ini:", bundle: .module)
                            Text(verbatim: initiativeValue ?? "")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(initiativeValue == nil ? .tertiary : .primary)
                    .help(Text("Choose the Initiative value", bundle: .module))
#if os(iOS) || os(macOS) || os(visionOS)
                    .battleLinkCharacterDropDestination(action: valueDropAction(kind: .initiative))
#endif

                    // Computed once and reused below: `hitPointsValue` walks a
                    // linked entry's formula chain, so reading it a second time
                    // purely for the color check would redo that work for no
                    // benefit. See CODE_AUDIT §7.1.
                    let hp = hitPointsValue
                    Button(action: selectHitPointsEntry) {
                        HStack(spacing: BattleRoundSpacing.extraTight) {
                            Text("HP:", bundle: .module)
                            Text(verbatim: hp ?? "")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(hp == nil ? .tertiary : .primary)
                    .help(Text("Choose the Hit Points value", bundle: .module))
#if os(iOS) || os(macOS) || os(visionOS)
                    .battleLinkCharacterDropDestination(action: valueDropAction(kind: .hitPoints))
#endif
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

                BattleRollResults(results: presentation.rolls, tint: tint)
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

    private func selectHitPointsEntry() {
        selectHitPoints(combatant)
    }

    private func selectInitiativeEntry() {
        selectInitiative(combatant)
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
    /// three action closures are excluded for the same reason
    /// `BattleRoundCard` excludes its own: never `Equatable`, and stable
    /// once hoisted to method references at the call site (see
    /// `BattleRoundView`).
    ///
    /// `nameMaxWidth` (a `@ScaledMetric`, driven by `\.sizeCategory`) is
    /// deliberately excluded too, for the same reason `BattleRoundCard`
    /// excludes `accessibilityReduceMotion`: it can only be read correctly
    /// from a real installed view, so comparing it here would either always
    /// see the environment default (masking real Dynamic Type changes) or
    /// reintroduce the exact bug `fd8ed359` fixed for `cardLayout`. The
    /// accepted tradeoff is that a Dynamic Type size change may not widen a
    /// truncated name until some other compared field changes and forces a
    /// real re-render. See CODE_AUDIT §8.3.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state === rhs.state
            && lhs.presentation == rhs.presentation
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
                isActive: true,
                tint: .red,
                controller: controller,
                showCharacter: { _ in },
                selectHitPoints: { _ in },
                selectInitiative: { _ in }
            )
            .padding()
        }
    }
}
