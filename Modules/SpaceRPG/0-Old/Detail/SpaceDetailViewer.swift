// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SpaceDetailViewer: View {
    let item: ItemRowTreeModel
    
    @Environment(SpaceRootModel.self) private var root
    @Environment(\.routeActions) private var routeActions

    var body: some View {
        Group {
#if os(tvOS)
            SpaceQuickLook(root: root, item: ItemSelection(itemId: item.model.itemId, entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .environment(SelectionSheetLinkModel())
#else
            SpaceViewer(root: root, id: item.model.itemId, isModal: false)
#endif
        }
        .environment(\.showGame, true)
        .overlay(alignment: .topTrailing) {
            Button {
                routeActions.routePage(root.itemController.itemDataModel.networkModule, item.model.itemId, item.model.entryId)
            } label: {
                Image(systemName: root.itemController.itemDataModel.networkModule.icon)
            }
            .padding()
        }
        .padding()
    }
}
