// @copyright André Trettin

import CoreRPG
import SwiftUI
import TipKit

struct AddLinkButton: View {
    let root: MapRootModel
    let model: MapModel
    let module: NetworkModules

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            withAnimation {
                navigator.navigate(
                    to: MapEditorRoute.addLink(
                        ItemRowModel(itemId: model.id, typeId: module)
                    )
                )
            }
        } label: {
            Label {
                Text("Link", bundle: .module)
            } icon: {
                Image(systemName: module.icon)
            }
        }
        .popoverTip(MasterRPGTips.linkContent)
    }
}

#Preview(traits: .mockData) {
    AddLinkButton(root: .preview, model: .preview, module: .photo)
}
