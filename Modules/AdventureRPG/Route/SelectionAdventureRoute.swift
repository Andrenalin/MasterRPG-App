// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

public enum SelectionAdventureRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionAdventureRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionRootView()
        }
    }
}
