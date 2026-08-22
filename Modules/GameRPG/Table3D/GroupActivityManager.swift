// @copyright André Trettin

#if os(visionOS)
import GroupActivities
import SwiftUI
@preconcurrency import TabletopKit

@MainActor @Observable
class GroupActivityManager {
    var tabletopGame: TabletopGame

    /// `gameTableModel` is threaded through to `RPGSharePlayController.setup(tabletopGame:gameTableModel:)`
    /// so seat assignment can be chained *after* `coordinateWithSession(_:)` there instead of
    /// being triggered separately and synchronously by the caller — see that method's own doc.
    init(tabletopGame: TabletopGame, gameTableModel: GameTableModel, sharePlayController: RPGSharePlayController) {
        self.tabletopGame = tabletopGame
        sharePlayController.setup(tabletopGame: tabletopGame, gameTableModel: gameTableModel)
    }

    isolated deinit {
        tabletopGame.detachNetworkCoordinator()
    }
}

#endif
