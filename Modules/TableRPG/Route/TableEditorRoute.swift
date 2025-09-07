// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
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
        if let tableModel {
            QuickEntryEditor(editController: root.editController, currentModel: tableModel)
        }
    }
    
    var tableModel: TableDataModel? {
        root.itemController.model(for: root.listControllable.listModel.selectedItemId)
    }
}
