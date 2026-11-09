// @copyright André Trettin

#if os(visionOS)
import GroupActivities
import SwiftUI
import TabletopKit

/// Ties the SharePlay coordination of the table to the lifetime of its view: creating it sets
/// the controller up for `tabletopGame`, and dropping it detaches the network coordinator again.
/// The view owns it in `@State`, so it lives as long as the table window.
@MainActor
final class GroupActivityManager {
    let tabletopGame: TabletopGame

    /// `gameTableModel` goes to `RPGSharePlayController.setup(tabletopGame:gameTableModel:)`, which
    /// assigns the seats after `coordinateWithSession(_:)`.
    init(tabletopGame: TabletopGame, gameTableModel: GameTableModel, sharePlayController: RPGSharePlayController) {
        self.tabletopGame = tabletopGame
        sharePlayController.setup(tabletopGame: tabletopGame, gameTableModel: gameTableModel)
    }

    isolated deinit {
        tabletopGame.detachNetworkCoordinator()
    }
}

#endif
