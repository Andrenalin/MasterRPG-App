// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum SelectionMapRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionMapRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            LinkRootView(type: .selection)
        }
    }
}
