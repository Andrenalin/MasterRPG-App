// @copyright André Trettin

import CoreRPG

import PdfRPG
import SwiftUI

enum EditorRoute: Equatable, Hashable, Codable {
    case quickEditor
    case selectionPdf
    case linkSelection(UUID)
    case addLink(NetworkModules)
}

extension EditorRoute: NavigationDestination {
    public var body: some View {
        DestinationEditorRoute(route: self)
    }
}

struct DestinationEditorRoute: View {
    let route: EditorRoute
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .quickEditor:
            QuickEntryEditor()
        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.adventureEditModel.selectionPdf)
        case .linkSelection(let entryId):
            EditorLinkView(root: root.rootController, editorLinkModel: root.editorLinkModel, selectedEntryId: entryId)
        case .addLink(let module):
            EditorLinkView(root: root.rootController, editorLinkModel: root.editorLinkModel, selectedModule: module, selectedEntryId: root.editController.editorModel.currentEntryId)
        }
    }
}
