// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

public enum SelectionPdfRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionPdfRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionRootView()
        }
    }
}
