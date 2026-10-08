// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AppInitialRouteTypeDestinationView: View {
    let route: AppInitialRouteType

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
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
        .environmentSetUp(AppModel())
        .appSettingsSetUp(AppModel())
}
