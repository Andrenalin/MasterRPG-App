// @copyright André Trettin

import SwiftUI
import CoreRPG

struct DicePlayer: View {
    let filterout: UUID
    let alignment: HorizontalAlignment

    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) var diceDisplayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            ForEach(playerDice) { player in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: alignment) {
                        playerButton(playerId: player.id)

                        if !root.gameController.isPlayerHidden(playerId: player.id) {
                            playerDice(playerId: player.id)
                        }
                    }
                    .animation(
                        Animation.bouncy.reduced(if: reduceMotion),
                        value: root.gameController.isPlayerHidden(playerId: player.id)
                    )
                }
            }
        }
    }

    private var playerDice: [DiceModel] {
        root.gameController.diceGameModel.playerDice.filter {
            diceDisplayModel.isEditing || !root.gameController.isPlayerHidden(playerId: $0.id)
        }
    }

    @ViewBuilder
    private func playerButton(playerId: UUID) -> some View {
        if diceDisplayModel.isEditing {
            Button {
                Task {
                    await root.gameController.toggleHidden(playerId: playerId)
                }
            } label: {
                DicePlayerLabel(playerId: playerId, isEditing: true)
            }
            .accessibilityLabel(
                root.gameController.isPlayerHidden(playerId: playerId)
                ? Text("Show \(playerName(playerId: playerId)) dice", bundle: .module)
                : Text("Hide \(playerName(playerId: playerId)) dice", bundle: .module)
            )
            .gameOverlayCapsuleControlStyle(
                isSelected: !root.gameController.isPlayerHidden(playerId: playerId)
            )
            .opacity(0.75)
        } else {
            DicePlayerLabel(playerId: playerId, isEditing: false)
                .padding(8)
                .contentShape(.capsule)
#if !os(visionOS)
                .glassEffect(.regular.interactive(), in: .capsule)
#endif
        }
    }

    private func playerName(playerId: UUID) -> String {
        DicePlayerLabel.playerName(of: root.gameController.gameItem(for: playerId))
    }

    private func playerDice(playerId: UUID) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(root.gameController.gameItem(for: playerId).dice) { die in
                VStack {
                    DieViewerView(gameController: root.gameController, diceId: playerId, die: die, withoutResult: false, resultColor: resultColor(for: die.id, playerId: playerId))
                        .padding(4)
                    Spacer()
                }
                .frame(height: root.viewController.height(for: root.gameController.gameItem(for: playerId)))
            }
        }
    }

    private func resultColor(for dieId: UUID, playerId: UUID) -> [Bool] {
        root.gameController.resultColor(for: dieId, itemId: playerId)
    }
}

/// A player's name, supporter crown and the result of the dice they last shared. Also the dice
/// result of another seat on the 3D table.
struct DicePlayerLabel: View {
    let playerId: UUID
    let isEditing: Bool

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(verbatim: Self.playerName(of: root.gameController.gameItem(for: playerId)))
                .lineLimit(1)
                .truncationMode(.head)
                .font(.footnote)

            SupporterCrownView(
                tier: root.gameController.supporterTier(playerId: playerId)
            )
            .font(.footnote)
            .fixedSize()

            if root.gameController.gameItem(for: playerId).sumUp || root.gameController.gameItem(for: playerId).compareOption != .off {
                Label {
                    Text(root.gameController.resultText(itemId: playerId).markDown())
                } icon: {
                    Image(systemName: root.gameController.result(itemId: playerId).checked ? "checkmark" : "xmark")
                }
                    .font(.footnote)
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }

            if isEditing {
                Image(systemName: root.gameController.isPlayerHidden(playerId: playerId) ? "plus.circle" : "x.circle.fill")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The player's first name.
    static func playerName(of dice: DiceModel) -> String {
        let name = dice.name
        if let firstName = name.split(separator: " ").first {
            return String(firstName)
        }
        return name
    }
}

#Preview {
    @Previewable @State var isEditing: Bool = false
    DicePlayer(filterout: DiceModel.previewId, alignment: .leading)
        .environment(DiceRootModel.preview)
        .environment(DiceDisplayModel())
}
