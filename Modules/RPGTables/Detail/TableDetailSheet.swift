// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct TableDetailSheet: View {
    let item: ItemRowTreeModel
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.routeActions) private var routeActions
    
    var body: some View {
        TableSheet(model: model, showTopImage: true, dismissAction: nil)
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
    
    var model: TableModel {
        root.itemController.itemOrEmpty(for: item.model.itemId)
    }
}

#Preview {
    TableDetailSheet(item: .preview)
        .environment(TableRootModel.previewWithData)
}
