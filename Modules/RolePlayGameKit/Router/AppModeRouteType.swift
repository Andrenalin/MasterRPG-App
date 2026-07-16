// @copyright André Trettin

import CoreRPG
import SwiftUI

extension AppModeRouteType: @retroactive NavigationDestination {
    public var body: some View {
        AppGameTypeDestinationView(type: self)
    }
}
