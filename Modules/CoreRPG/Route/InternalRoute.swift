// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

enum InternalRoute: Equatable, Codable {
    case export(ids: [UUID])
    case removeAlert
}

extension InternalRoute: NavigationDestination {
    var body: some View {
        InternalRouteDestinationView(route: self)
    }
}

struct InternalRouteDestinationView: View {
    let route: InternalRoute
    
    @Environment(ItemRootController.self) private var root
    
    var body: some View {
        switch route {
        case .export(let ids):
            ExportProgressFile(exportController: root.exportControllable) {
                let exportIds = root.exportControllable.exporting(ids: Set(ids))
                return root.exportControllable.export(ids: exportIds)
            }
            .presentationDetents([.height(160)])
        case .removeAlert:
            EffectedLinkAction(itemControllable: root.itemControllable) { models in
                models.forEach {
                    if let item = ItemDataModel.model(modelContext: root.itemControllable.container.mainContext, id: $0.itemId) {
                        root.editControllable.delete(item: item)
                    }
                }
            }
            .environment(root.removeEntryListModel)
        }
    }
}
