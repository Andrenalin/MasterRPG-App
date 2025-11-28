// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum SelectionAdventureRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionAdventureRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            LinkRootView(type: .selection)
        }
    }
}
