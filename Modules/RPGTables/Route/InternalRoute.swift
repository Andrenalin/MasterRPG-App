// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI
import RPGPdfs

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
    
    @Environment(TableRoot.self) private var root
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
            root.pdfRoot.viewController.selectForScanning(model: editController.tableEditModel.pdfSelectionModel)
        }
    }
    
    var editController: EditController {
        root.editController(type: .main)
    }
}
