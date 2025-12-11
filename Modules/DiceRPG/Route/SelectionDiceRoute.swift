// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SelectionDiceRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionDiceRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionDiceRouteDestinationView()
        }
    }
}

struct SelectionDiceRouteDestinationView: View {
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection)
            .environment(root.rootController)
            .environment(root.itemSelectionModel)
    }
}
