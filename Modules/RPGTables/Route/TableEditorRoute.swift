// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum TableEditorRoute: Equatable, Hashable, Codable {
    case quickEditor
}

extension TableEditorRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .quickEditor:
            DestinationTableEditorRoute()
        }
    }
}

struct DestinationTableEditorRoute: View {
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        QuickEntryEditor(editController: root.editController)
    }
}
