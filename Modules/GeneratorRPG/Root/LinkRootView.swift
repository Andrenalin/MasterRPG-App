// @copyright André Trettin

import CoreRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType
    let itemSelectionModel: ItemSelectionModel

    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root.rootController, type: type, itemSelectionModel: itemSelectionModel)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window, itemSelectionModel: ItemSelectionModel())
}
