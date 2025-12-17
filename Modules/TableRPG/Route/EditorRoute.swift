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
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.tableEditModel.selectionPdf)
        case .linkSelection(let entryId):
            EditorLinkView(root: root.rootController, editorLinkModel: root.editorLinkModel, selectedEntryId: entryId)
        case .addLink(let module):
            EditorLinkView(root: root.rootController, editorLinkModel: root.editorLinkModel, selectedModule: module, selectedEntryId: root.editController.editorModel.currentEntryId)
        }
    }
}
