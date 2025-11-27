// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import PdfRPG
import SwiftUI

public enum EditorRoute: Equatable, Hashable, Codable {
    case quickEditor
    case selectionPdf
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
            QuickEntryEditor(editController: root.editController)
        case .selectionPdf:
            root.pdfRoot.viewController.selectionView( model: root.editController.tableEditModel.selectionPdf)
        }
    }
}
