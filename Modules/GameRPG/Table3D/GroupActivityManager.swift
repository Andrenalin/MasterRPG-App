// @copyright André Trettin

#if os(visionOS)
import GroupActivities
import SwiftUI
@preconcurrency import TabletopKit

class GroupActivityManager: Observable {
    var tabletopGame: TabletopGame
    var sessionTask = Task<Void, Never> {}
    
    @MainActor
    init(tabletopGame: TabletopGame) {
        self.tabletopGame = tabletopGame
        sessionTask = Task {
            for await session in RPGActivity.sessions() {
                tabletopGame.coordinateWithSession(session)
            }
        }
    }

    deinit {
        tabletopGame.detachNetworkCoordinator()
    }
}

#endif
