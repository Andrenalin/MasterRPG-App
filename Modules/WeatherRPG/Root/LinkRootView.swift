// @copyright André Trettin

import CoreRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root.rootController, type: type)
            .environment(root.rootController)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window)
}
