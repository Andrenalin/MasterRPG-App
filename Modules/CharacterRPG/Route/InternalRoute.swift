// @copyright André Trettin


import CoreRPG
import SwiftUI
import PdfRPG

enum InternalRoute: Hashable, Codable {
    case editDetail(UUID)
    case linkEditor
    case quickEditor
    case selectPdf
}

extension InternalRoute: NavigationDestination {
    var body: some View {
        InternalRouteView(route: self)
    }
}

struct InternalRouteView: View {
    let route: InternalRoute
    
    @Environment(CharacterRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        switch route {
        case .editDetail(let itemId):
            RootEditDetail(itemId: itemId)
        case .linkEditor:
            RootQuickLinkEditor(editController: editController)
        case .quickEditor:
            QuickEntryEditor(editController: editController)
        case .selectPdf:
            root.pdfRoot.viewController.selectForScanning(root: root.pdfRoot, model: editController.valueEditModel.pdfSelectionModel)
        }
    }
    
    var editController: EditController {
        root.editController
    }
}
