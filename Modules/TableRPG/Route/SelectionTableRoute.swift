// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SelectionTableRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionTableRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionTableRouteDestinationView()
        }
    }
}

struct SelectionTableRouteDestinationView: View {
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: root.itemSelectionModel)
    }
}
