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

    @Environment(SpaceRootModel.self) private var root

    var body: some View {
        switch route {
            case .export(let ids):
            Text("")
//                ExportProgressFile(exportController: root.exportController) {
//                    let exportIds = root.exportController.exporting(ids: Set(ids))
//                    return root.exportController.export(ids: exportIds)
//                }
                .presentationDetents([.height(160)])
        }
    }
}
