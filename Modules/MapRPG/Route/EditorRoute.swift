// @copyright André Trettin

import CoreRPG

import PdfRPG
import SwiftUI

enum EditorRoute: Equatable, Hashable, Codable {
    case mapEditor
    case quickEditor
    case selectionPdf
    case linkSelection(UUID)
}

extension EditorRoute: NavigationDestination {
    public var body: some View {
        DestinationEditorRoute(route: self)
    }
}

struct DestinationEditorRoute: View {
    let route: EditorRoute
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .mapEditor:
            MapEditWindow(editController: root.editController)
        case .quickEditor:
            QuickEntryEditor()
        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.mapEditModel.selectionPdf)
        case .linkSelection(let entryId):
            EditorLinkView()
        }
    }
}
