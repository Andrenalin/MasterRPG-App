// @copyright André Trettin

import CoreRPG
import SwiftUI

extension AppModeRouteType: @retroactive NavigationDestination {
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        AppGameTypeDestinationView(type: self)
    }
}
