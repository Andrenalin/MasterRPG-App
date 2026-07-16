// @copyright André Trettin

import CoreRPG
import SwiftUI

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

#Preview("Database initialization destination") {
    AppInitialRouteTypeDestinationView(route: .initializing)
        .environment(AppModel())
}
