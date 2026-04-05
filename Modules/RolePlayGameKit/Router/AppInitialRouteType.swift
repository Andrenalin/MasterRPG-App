// @copyright André Trettin

import CoreRPG
import SwiftUI

extension AppInitialRouteType: @retroactive NavigationDestination {
    public var body: some View {
        AppInitialRouteTypeDestinationView(route: self)
    }
}

struct AppInitialRouteTypeDestinationView: View {
    let route: AppInitialRouteType
    
    var body: some View {
        switch route {
        case .initializing:
            DatabaseInitializationView()
        case .ready:
            DestinationReadyView()
        }
    }
}
