// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

public enum SelectionCharacterRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionCharacterRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionRootView()
        }
    }
}
