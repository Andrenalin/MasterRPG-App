// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

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

#Preview(traits: .mockData) {
    ImportRouteDestinationView(route: .importGame)
}
