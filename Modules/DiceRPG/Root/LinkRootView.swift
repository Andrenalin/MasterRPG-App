// @copyright André Trettin

import CoreRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root.rootController, type: type)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window)
}
