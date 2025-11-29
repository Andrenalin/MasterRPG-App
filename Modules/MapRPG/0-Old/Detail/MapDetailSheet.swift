// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapDetailSheet: View {
    let item: ItemRowTreeModel
    
    @Environment(MapRootModel.self) private var root
    @Environment(\.routeActions) private var routeActions
    
    var body: some View {
        MapSheet(model: model, showTopImage: true, dismissAction: nil)
            .environment(\.showGame, true)
            .overlay(alignment: .topTrailing) {
                Button {
                    routeActions.routePage(root.itemController.itemDataModel.networkModule, item.model.itemId, item.model.entryId)
                } label: {
                    Image(systemName: root.itemController.itemDataModel.networkModule.icon)
                }
                .padding()
            }
    }
    
    var model: MapModel {
        root.itemController.itemOrEmpty(for: item.model.itemId)
    }
}

#Preview {
    MapDetailSheet(item: .preview)
        .environment(MapRootModel.previewWithData)
}
