// @copyright André Trettin

import GroupActivities
import SwiftUI
@preconcurrency import TabletopKit

//struct Activity: GroupActivity {
//    var metadata: GroupActivityMetadata {
//        var metadata = GroupActivityMetadata()
//        metadata.type = .generic
//        metadata.title = "TabletopKitSample"
//        return metadata
//    }
//}

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
