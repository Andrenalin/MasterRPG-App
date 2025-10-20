// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public enum SelectionModuleRoute: Equatable, Hashable, Codable {
    case selection
}

extension SelectionModuleRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .selection:
            SelectionModuleDestinationView()
        }
    }
}

struct SelectionModuleDestinationView: View {
    @Environment(ItemRootController.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root, type: .selection)
    }
}
