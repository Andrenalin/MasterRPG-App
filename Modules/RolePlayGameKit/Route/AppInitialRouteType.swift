// @copyright André Trettin

import CoreRPG
import SwiftUI

extension AppInitialRouteType: @retroactive NavigationDestination {
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        AppInitialRouteTypeDestinationView(route: self)
    }
}
