// @copyright André Trettin

import CoreRPG
import SwiftUI

extension AppInitialRouteType: @retroactive NavigationDestination {
    public var body: some View {
        AppInitialRouteTypeDestinationView(route: self)
    }
}
