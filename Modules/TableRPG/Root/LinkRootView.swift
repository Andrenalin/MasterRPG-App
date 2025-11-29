// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root.rootController, type: type)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window)
}
