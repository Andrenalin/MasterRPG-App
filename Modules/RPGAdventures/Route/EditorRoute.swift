// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
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
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .quickEditor:
            QuickEntryEditor(editController: root.editController)
        case .selectionPdf:
            root.pdfRoot.viewController.selectionView( model: root.editController.adventureEditModel.selectionPdf)
        }
    }
}
