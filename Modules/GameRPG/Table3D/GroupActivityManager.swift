// @copyright André Trettin

#if os(visionOS)
import GroupActivities
import SwiftUI
@preconcurrency import TabletopKit

@MainActor
class GroupActivityManager: Observable {
    var tabletopGame: TabletopGame

    init(tabletopGame: TabletopGame, sharePlayController: RPGSharePlayController) {
        self.tabletopGame = tabletopGame
        sharePlayController.setup(tabletopGame: tabletopGame)
    }

    isolated deinit {
        tabletopGame.detachNetworkCoordinator()
    }
}

#endif
