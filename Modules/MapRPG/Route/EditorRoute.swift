// @copyright André Trettin

import CoreRPG

import PdfRPG
import SwiftUI

enum EditorRoute: Equatable, Hashable, Codable {
    case quickEditor
    case selectionPdf
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
        case .quickEditor:
            QuickEntryEditor()
        case .selectionPdf:
            root.pdfRoot.viewController.selectionView( model: root.editController.mapEditModel.selectionPdf)
        }
    }
}
