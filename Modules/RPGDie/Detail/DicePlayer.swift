// @copyright André Trettin

import SwiftUI

struct DicePlayer: View {
    let filterout: UUID
    let alignment: HorizontalAlignment

    @Environment(DiceRoot.self) private var root
    @Environment(DiceDisplayModel.self) var diceDisplayModel

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
                    .animation(.bouncy, value: root.gameController.isPlayerHidden(playerId: player.id))
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
        Button {
            guard diceDisplayModel.isEditing else { return }
            Task {
                await root.gameController.toggleHidden(playerId: playerId)
            }
        } label: {
            playerLabel(playerId: playerId)
        }
        .buttonStyle(.borderedProminent)
        .opacity(0.75)
    }

    @ViewBuilder
    private func playerLabel(playerId: UUID) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(playerName(playerId: playerId))
                .lineLimit(1)
                .truncationMode(.head)
                .font(.footnote)

            if root.gameController.gameItem(for: playerId).sumUp || root.gameController.gameItem(for: playerId).compareOption != .off {
                Label("\(root.gameController.resultText(itemId: playerId).markDown())", systemImage: root.gameController.result(itemId: playerId).checked ? "checkmark" : "xmark")
                    .font(.footnote)
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }

            if diceDisplayModel.isEditing {
                Image(systemName: root.gameController.isPlayerHidden(playerId: playerId) ? "plus.circle" : "x.circle.fill")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }
        }
        .fixedSize()
    }

    private func playerName(playerId: UUID) -> String {
        let name = root.gameController.gameItem(for: playerId).name
        if let firstName = name.split(separator: " ").first {
            return String(firstName)
        }
        return name
    }

    private func playerDice(playerId: UUID) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(root.gameController.gameItem(for: playerId).entries) { die in
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
        let result = root.gameController.diceSuccess(for: playerId)
        guard let colors = result.first(where: { $0.0 == dieId }) else { return [] }
        return colors.1
    }
}

#Preview {
    @Previewable @State var isEditing: Bool = false
    DicePlayer(filterout: DiceModel.previewId, alignment: .leading)
        .environment(DiceRoot.preview)
        .environment(DiceDisplayModel())
}
