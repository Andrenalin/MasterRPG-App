// @copyright André Trettin

import CoreRPG
import SwiftUI

enum AppInitialStateRoute: Codable, Equatable, Hashable {
    case initializing
    case ready
}

extension AppInitialStateRoute: NavigationDestination {
    var body: some View {
        AppInitialStateRouteDestinationView(route: self)
    }
}

struct AppInitialStateRouteDestinationView: View {
    let route: AppInitialStateRoute
    
    var body: some View {
        switch route {
        case .initializing:
            DatabaseInitializationView()
        case .ready:
            DestinationReadyView()
        }
    }
}
