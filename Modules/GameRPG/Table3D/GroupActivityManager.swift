// @copyright André Trettin

#if os(visionOS)
import GroupActivities
import SwiftUI
@preconcurrency import TabletopKit

class GroupActivityManager: Observable {
    var tabletopGame: TabletopGame

    @MainActor
    init(tabletopGame: TabletopGame, sharePlayController: RPGSharePlayController) {
        self.tabletopGame = tabletopGame
        sharePlayController.setup(tabletopGame: tabletopGame)
    }

    deinit {
        tabletopGame.detachNetworkCoordinator()
    }
}

#endif
