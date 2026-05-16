// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SelectionCharacterRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionCharacterRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            DestinationSelectionCharacterRoute()
        }
    }
}

struct DestinationSelectionCharacterRoute: View {
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: root.itemSelectionModel)
    }
}
