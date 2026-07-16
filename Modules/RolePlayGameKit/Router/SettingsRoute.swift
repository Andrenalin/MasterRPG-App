// @copyright André Trettin

import CoreRPG
import SwiftUI

enum SettingsRoute {
    case exportData
    case importData
    case validate
}

extension SettingsRoute: NavigationDestination {
    var body: some View {
        SettingsRouteDestinationView(route: self)
    }
}
