// @copyright André Trettin

import CoreRPG
import SwiftUI
import TipKit

struct AddLinkButton: View {
    let root: TableRootModel
    let model: TableModel
    let module: NetworkModules

    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                navigator.navigate(
                    to: TableEditorRoute.addLink(
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
