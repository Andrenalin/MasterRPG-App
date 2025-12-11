// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SelectionAdventureRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionAdventureRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionAdventureRouteDestinationView()
        }
    }
}

struct SelectionAdventureRouteDestinationView: View {
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection)
            .environment(root.rootController)
            .environment(root.itemSelectionModel)
    }
}
