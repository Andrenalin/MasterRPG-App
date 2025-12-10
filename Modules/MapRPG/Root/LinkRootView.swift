// @copyright André Trettin

import CoreRPG
import CharacterRPG
import DiceRPG
import TableRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root.rootController, type: type)
            .environment(root.rootController)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window)
}
