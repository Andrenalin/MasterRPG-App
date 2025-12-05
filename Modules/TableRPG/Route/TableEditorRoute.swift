// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import SwiftUI

public enum EditorRoute: Equatable, Hashable, Codable {
    case quickEditor
    case selectionPdf
    case linkSelection(UUID)
    case addLink(NetworkModules)
}

extension EditorRoute: NavigationDestination {
    public var body: some View {
        DestinationTableEditorRoute(route: self)
    }
}

struct DestinationTableEditorRoute: View {
    let route: EditorRoute
    
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .quickEditor:
            QuickEntryEditor()
        case .selectionPdf:
            root.pdfRoot.viewController.selectionView(model: root.editController.tableEditModel.selectionPdf)
        case .linkSelection(let entryId):
            EditorLinkView()
        case .addLink(let module):
            switch module {
            case .dice:
                root.diceRoot.viewController.selectionView(model: root.editController.tableEditModel.addLinkDice)
            default:
                root.viewController.selectionView(model: root.editController.tableEditModel.addLinkTable)
            }
        }
    }
}
