// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG

enum ImportRoute {
    case importGame
}

extension ImportRoute: NavigationDestination {
    var body: some View {
        ImportRouteDestinationView(route: self)
    }
}

struct ImportRouteDestinationView: View {
    let route: ImportRoute
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .importGame:
            ImportProgressPanelView(importController: root.importControllable)
        }
    }
}
