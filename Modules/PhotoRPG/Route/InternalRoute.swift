// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

enum InternalRoute: Equatable, Codable {
    case export(ids: [UUID])
}

extension InternalRoute: NavigationDestination {
    var body: some View {
        InternalRouteDestinationView(route: self)
    }
}

struct InternalRouteDestinationView: View {
    let route: InternalRoute
    
    @Environment(PhotoRootModel.self) private var rootModel
    
    var body: some View {
        switch route {
        case .export(let ids):
            ExportProgressFile(exportController: rootModel.exportController) {
                let exportIds = rootModel.exportController.exporting(ids: Set(ids))
                return rootModel.exportController.export(ids: exportIds)
            }
            .presentationDetents([.height(160)])
        }
    }
}
