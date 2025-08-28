// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

public enum SelectionPhotoRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionPhotoRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionDestinationView()
        }
    }
}

struct SelectionDestinationView: View {
    var body: some View {
        SelectionRootView()
    }
}
