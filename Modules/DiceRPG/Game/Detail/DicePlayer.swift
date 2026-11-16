// @copyright André Trettin

import SwiftUI
import CoreRPG

struct DicePlayer: View {
    let alignment: HorizontalAlignment

    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) var diceDisplayModel

    public var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            ForEach(playerDice) { player in
                DicePlayerRow(playerId: player.id, alignment: alignment)
            }
        }
    }

    private var playerDice: [DiceModel] {
        root.gameController.diceGameModel.playerDice.filter {
            diceDisplayModel.isEditing || !root.gameController.isPlayerHidden(playerId: $0.id)
        }
    }
}

/// One player's button and, unless hidden, the dice they shared.
private struct DicePlayerRow: View {
    let playerId: UUID
    let alignment: HorizontalAlignment

    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: alignment) {
                DicePlayerButton(playerId: playerId)

                if !root.gameController.isPlayerHidden(playerId: playerId) {
                    DiceBagRow(playerId: playerId)
                }
            }
            .animation(
                Animation.bouncy.reduced(if: reduceMotion),
                value: root.gameController.isPlayerHidden(playerId: playerId)
            )
        }
    }
}

/// The player's name: a toggle that hides or shows their dice while editing, a plain capsule otherwise.
private struct DicePlayerButton: View {
    let playerId: UUID

    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) private var diceDisplayModel

    var body: some View {
        if diceDisplayModel.isEditing {
            Button {
                root.gameController.toggleHidden(playerId: playerId)
            } label: {
                DicePlayerLabel(playerId: playerId, isEditing: true)
            }
            .accessibilityLabel(
                root.gameController.isPlayerHidden(playerId: playerId)
                ? Text("Show \(playerName) dice", bundle: .module)
                : Text("Hide \(playerName) dice", bundle: .module)
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

    private var playerName: String {
        DicePlayerLabel.playerName(of: root.gameController.gameItem(for: playerId))
    }
}

/// The dice a player shared, with their last results.
private struct DiceBagRow: View {
    let playerId: UUID

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(root.gameController.gameItem(for: playerId).dice) { die in
                VStack {
                    DieViewerView(gameController: root.gameController, diceId: playerId, die: die, withoutResult: false, resultColor: root.gameController.resultColor(for: die.id, itemId: playerId))
                        .padding(4)
                    Spacer()
                }
                .frame(height: root.viewController.height(for: root.gameController.gameItem(for: playerId)))
            }
        }
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
    DicePlayer(alignment: .leading)
        .environment(DiceRootModel.preview)
        .environment(DiceDisplayModel())
}
