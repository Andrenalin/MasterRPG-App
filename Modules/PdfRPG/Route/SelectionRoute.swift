// @copyright André Trettin

import CoreRPG
import SwiftUI

enum SelectionRoute: Equatable, Hashable, Codable {
    case selection
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
    @Environment(PdfRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: root.itemSelectionModel)
    }
}
