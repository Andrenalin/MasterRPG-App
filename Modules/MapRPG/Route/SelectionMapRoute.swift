// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SelectionMapRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionMapRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionMapRouteDestinationView()
        }
    }
}

struct SelectionMapRouteDestinationView: View {
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection)
            .environment(root.rootController)
            .environment(root.itemSelectionModel)
    }
}
