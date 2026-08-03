// @copyright André Trettin

import CharacterRPG
import CoreRPG
import MapRPG
import PhotoRPG
import SwiftUI

struct BattleParticipantColumn: View {
    let state: BattleRoundCardState
    let presentation: BattleRoundParticipantPresentation
    let isAttacker: Bool
    let isActive: Bool
    let tint: Color
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

    private var root: MapRootModel { controller.root.mapRoot }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: openCharacter) {
                ZStack {
                    controller.root.photoRoot.viewController.mapImage(
                        root: controller.root.photoRoot,
                        for: combatant.photoId,
                        size: CGSize(width: 48, height: 48),
                        color: combatant.color
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(.circle)

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
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .bottomTrailing
                            )
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
#if os(iOS) || os(macOS) || os(visionOS)
            .battleLinkCharacterDropDestination { characters, _ in
                guard let character = characters.first else { return false }
                controller.assignCharacter(combatant.id, character.itemId)
                return true
            }
#endif

            Button(
                combatant.isDead ? "Mark Alive" : "Mark Dead",
                systemImage: combatant.isDead ? "heart.fill" : "skull.fill",
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

            Button(action: selectInitiativeEntry) {
                HStack(spacing: 2) {
                    Text("Ini", bundle: .module)
                    Text(verbatim: initiativeValue ?? "")
                        .monospacedDigit()
                }
                .font(.caption2)
                .frame(minWidth: 48, minHeight: 20)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(initiativeValue == nil ? .tertiary : .primary)
            .help(Text("Choose the Initiative value", bundle: .module))
#if os(iOS) || os(macOS) || os(visionOS)
            .battleLinkCharacterDropDestination { values, _ in
                guard let value = values.first, let entryId = value.entryId else {
                    return false
                }
                return controller.assignValueEntry(
                    combatantId: combatant.id,
                    sourceCharacterId: value.itemId,
                    sourceEntryId: entryId,
                    kind: .initiative
                )
            }
#endif

            Button(action: selectHitPointsEntry) {
                HStack(spacing: 2) {
                    Text("HP", bundle: .module)
                    Text(verbatim: hitPointsValue ?? "")
                        .monospacedDigit()
                }
                .font(.caption2)
                .frame(minWidth: 48, minHeight: 20)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(hitPointsValue == nil ? .tertiary : .primary)
            .help(Text("Choose the Hit Points value", bundle: .module))
#if os(iOS) || os(macOS) || os(visionOS)
            .battleLinkCharacterDropDestination { values, _ in
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
                    kind: .hitPoints
                )
            }
#endif

            HStack(spacing: 6) {
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
            }

            BattleRollResults(results: presentation.rolls, tint: tint)

            if !isAttacker {
                Text(combatant.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
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
}

#Preview("Battle participant", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let participant = model.cardPresentations.first?.defenders.first {
        BattleParticipantColumn(
            state: BattleRoundCardState(),
            presentation: participant,
            isAttacker: false,
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
