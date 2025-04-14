// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PdfDetailViewer: View {
    let item: ItemRowTreeModel
    
    @Environment(PdfRoot.self) private var root
    @Environment(\.routeActions) private var routeActions

    var body: some View {
        root.viewController.pdfWindow(selection: ItemSelection(itemId: item.model.itemId, entryId: item.model.entryId))
            .environment(\.showGame, true)
            .padding(.top, 64)
            .overlay(alignment: .topTrailing) {
                Button {
                    routeActions.routePage(root.itemController.itemDataModel.networkModule, item.model.itemId, item.model.entryId)
                } label: {
                    Image(systemName: root.itemController.itemDataModel.networkModule.icon)
                }
                .padding()
        }
    }
}
