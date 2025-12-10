// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        LinkRootView(type: type)
            .environment(root.rootController)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window)
}
