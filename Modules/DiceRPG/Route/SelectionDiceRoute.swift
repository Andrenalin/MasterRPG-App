// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

public enum SelectionDiceRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionDiceRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionRootView()
        }
    }
}
