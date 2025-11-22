// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum SelectionPhotoRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionPhotoRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            LinkRootView(type: .selection)
        }
    }
}
