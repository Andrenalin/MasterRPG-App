// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureAddLinkButton: View {
    let root: AdventureRootModel
    let model: AdventureModel
    let module: NetworkModules
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                navigator.navigate(to: AdventureEditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)))
            }
        } label: {
            Label {
                Text("Link", bundle: .module)
            } icon: {
                Image(systemName: module.icon)
            }
        }
    }
}

#Preview(traits: .mockData) {
    AdventureAddLinkButton(root: .preview, model: .preview, module: .photo)
}
