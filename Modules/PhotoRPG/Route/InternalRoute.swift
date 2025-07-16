// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

enum InternalRoute: Equatable, Codable {
    case export(id: UUID)
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
        case .export(let id):
            ExportProgressFile(exportController: rootModel.exportController) {
                let ids = rootModel.exportController.exporting(ids: [id])
                return rootModel.exportController.export(ids: ids)
            }
        }
    }
}
