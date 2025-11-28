// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum SelectionCharacterRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionCharacterRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            LinkRootView(type: .selection)
        }
    }
}
