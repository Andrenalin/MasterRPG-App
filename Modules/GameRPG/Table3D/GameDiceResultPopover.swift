// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import DiceRPG
import MapRPG
import SwiftUI
import TabletopKit

// A dice result on the 3D table: the same popover as the pin action menu, standing above a
// group of dice once they have been rolled and lie still (`GameTableModel.shownDiceGroups`). A
// group is a seat's dice, or the dice of one player without a table, at the guest seat. What the
// popover shows is the dice overlay's result (`MasterGameScreen`/`PlayerGameScreen`): the focused
// dice's own result for this device's seat, and a player's entry, with the name, for any other.

/// The dice result popover as one of the table volume's per-group attachments.
@MainActor
struct GameDiceResultPopover: View {
    let root: GameRoot
    let game: GameTableModel
    let group: TableDiceGroup
    /// The table's dice display state, shared with its dice action bar: tapping the own result
    /// opens the quick value editor there and here.
    let diceDisplayModel: DiceDisplayModel
    /// The table scene's environment, handed on to the attachment.
    let appGameStateModel: AppGameStateModel?
    let networkActions: NetworkActions?

    @Environment(\.physicalMetrics) private var physicalMetrics

    private var content: GameDiceResultContent.Kind? {
        guard game.shownDiceGroups.contains(group) else { return nil }
        let dice = root.diceRoot.diceGameControllable
        let playerNames: [String]
        switch group {
        case .seat(let seat) where seat == game.localSeat:
            guard let focusId = dice.gameModel.focusItemIds.first,
                  dice.showsResult(for: focusId) else { return nil }
            return .own
        case .seat(let seat):
            guard isVisible(isMasterSeat: seat == Self.masterSeat) else { return nil }
            // Several players can share a seat; the overlay lists one result per player.
            playerNames = game.seatPlayerNames[seat] ?? []
        case .guest(let index):
            guard isVisible(isMasterSeat: false), game.guestGroups.indices.contains(index) else { return nil }
            playerNames = [game.guestGroups[index].name]
        }
        return playerNames.lazy
            .compactMap { dice.playerDiceId(named: $0) }
            .first
            .map { .player(diceId: $0) }
    }

    /// Whether this device may see another player's result.
    private func isVisible(isMasterSeat: Bool) -> Bool {
        TableDiceResultVisibility.isVisible(
            isLocalSeat: false,
            isGameMaster: game.isGameMaster,
            isMasterSeat: isMasterSeat,
            features: root.gameModel.gameControl.features
        )
    }

    var body: some View {
        let content = content
        ZStack {
            if let content {
                game.mapRoot.viewController.tablePopoverLabel(isInteractive: content == .own) {
                    GameDiceResultContent(root: root, kind: content)
                        // Half of the default `padding()` inset, as in the pin action menu.
                        .padding(8)
                }
                .environment(diceDisplayModel)
                .environment(appGameStateModel)
                .environment(\.networkActions, networkActions)
                // The model raises the attachment by half its height, so the arrow's tip, at
                // the bottom of this view, ends just above the dice.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    game.diceResultAttachmentHeightChanged(
                        Float(physicalMetrics.convert(height, to: .meters)),
                        for: group
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.default, value: content)
    }

    /// Seat 0 is always the game master (see `GameTableModel.assignSeatsForSharePlay`).
    static let masterSeat = TableSeatIdentifier(0)

    static func attachmentId(for group: TableDiceGroup) -> String {
        switch group {
        case .seat(let seat): "dice-result-seat-\(seat.rawValue)"
        case .guest(let index): "dice-result-guest-\(index)"
        }
    }
}

/// The dice overlay's result view for a seat.
private struct GameDiceResultContent: View {
    enum Kind: Equatable {
        /// This device's seat: the focused dice's result, as the overlay shows it.
        case own
        /// Another seat: the overlay's entry for the dice its player last shared.
        case player(diceId: UUID)
    }

    let root: GameRoot
    let kind: Kind

    var body: some View {
        switch kind {
        case .own:
            root.diceRoot.viewController.diceResultView(root: root.diceRoot)
        case .player(let diceId):
            root.diceRoot.viewController.dicePlayerResultView(root: root.diceRoot, diceId: diceId)
        }
    }
}
#endif
