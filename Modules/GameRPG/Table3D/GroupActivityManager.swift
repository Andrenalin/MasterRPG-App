// @copyright André Trettin

#if os(visionOS)
import GroupActivities
import SwiftUI
@preconcurrency import TabletopKit

class GroupActivityManager: Observable {
    var tabletopGame: TabletopGame
    var sessionTask = Task<Void, Never> {}
    
    @MainActor
    init(tabletopGame: TabletopGame, sharePlayController: RPGSharePlayController) {
        self.tabletopGame = tabletopGame
        sessionTask = Task {
            for await session in RPGActivity.sessions() {
                tabletopGame.coordinateWithSession(session)
            }
        }
        
        sharePlayController.setup(tabletopGame: tabletopGame)
    }

    deinit {
        tabletopGame.detachNetworkCoordinator()
    }
}

#endif
