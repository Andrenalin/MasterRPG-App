// @copyright André Trettin

import CoreRPG
import SwiftUI

enum SelectionRoute: Equatable, Hashable, Codable {
    case selection
    case mutliSelection
}

extension SelectionRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionDestinationView()
        case .mutliSelection:
            MultiSelectionDestinationView()
        }
    }
}

struct SelectionDestinationView: View {
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: root.itemSelectionModel)
    }
}

struct MultiSelectionDestinationView: View {
    @Environment(PhotoRootModel.self) private var root
    @Environment(ItemSelectionModel.self) private var itemSelectionModel
    
    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: itemSelectionModel)
    }
}
