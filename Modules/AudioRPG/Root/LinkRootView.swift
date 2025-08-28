// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(AudioRootModel.self) private var root

    var body: some View {
        CoreRPG.LinkRootView(root: root, type: type)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(type: .window)
}
