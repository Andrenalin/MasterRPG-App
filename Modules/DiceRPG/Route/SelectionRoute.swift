// @copyright André Trettin

import CoreRPG
import SwiftUI

enum SelectionRoute: Equatable, Hashable, Codable {
    case selection
}

#Preview(traits: .mockData) {
    SelectionDestinationView()
}

extension SelectionRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionDestinationView()
        }
    }
}

struct SelectionDestinationView: View {
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: root.itemSelectionModel)
    }
}
