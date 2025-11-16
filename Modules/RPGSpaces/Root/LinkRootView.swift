// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root.rootController, type: type)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window)
}
