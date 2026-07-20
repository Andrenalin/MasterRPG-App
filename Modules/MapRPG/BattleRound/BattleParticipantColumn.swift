// @copyright André Trettin

import CharacterRPG
import CoreRPG
import PhotoRPG
import SwiftUI

struct BattleParticipantColumn: View {
    let presentation: BattleRoundParticipantPresentation
    let isAttacker: Bool
    let isActive: Bool
    let tint: Color
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleCombatant) -> Void

    @Environment(MapRootModel.self) private var root

    var body: some View {
        VStack(spacing: 4) {
            Button(action: openCharacter) {
                ZStack {
                    root.photoRoot.viewController.mapImage(
                        root: root.photoRoot,
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
            .contextMenu {
                Button(
                    combatant.isDead ? "Mark Alive" : "Mark Dead",
                    systemImage: combatant.isDead ? "heart.fill" : "skull.fill",
                    action: toggleDead
                )
            }
#if os(iOS) || os(macOS) || os(visionOS)
            .dropDestination(for: LinkCharacterData.self) { characters, _ in
                guard let character = characters.first else { return }
                actions.assignCharacter(combatant.id, character.itemId)
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

    private var hasCharacter: Bool {
        combatant.gameCharacterId != nil || combatant.sourceCharacterId != nil
    }

    private func openCharacter() {
        showCharacter(combatant)
    }

    private func selectRollRecipient() {
        actions.selectRollRecipient(combatant.id)
    }

    private func toggleDead() {
        actions.setDead(combatant.id, !combatant.isDead)
    }
}
