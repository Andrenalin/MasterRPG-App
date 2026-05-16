// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SelectionPhotoRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionPhotoRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionPhotoRouteDestinationView()
        }
    }
}

struct SelectionPhotoRouteDestinationView: View {
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: root.itemSelectionModel)
    }
}
