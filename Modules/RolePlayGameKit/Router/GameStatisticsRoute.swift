// @copyright André Trettin

import CoreRPG
import SwiftUI

enum GameStatisticsRoute: Hashable, Codable {
    case dashboard
}

extension GameStatisticsRoute: NavigationDestination {
    var body: some View {
        GameStatisticsRouteDestinationView()
    }
}
