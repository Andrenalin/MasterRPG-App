// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PhotoDetailViewer: View {
    let item: ItemRowTreeModel
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(\.routeActions) private var routeActions

    var body: some View {
        RootPhotoViewer(model: model, toolBarModel: root.rootModel.toolbarModel, isGame: true)
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
    
    var model: PhotoModel {
        root.itemController.itemOrEmpty(for: item.model.itemId)
    }
}
