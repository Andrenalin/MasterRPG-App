// @copyright André Trettin

import CoreRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType

    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        LinkItemRootView(root: root.rootController, type: type)
            .environment(root.rootController)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack(name: "Test") {
        LinkRootView(type: .window)
            .environment(ItemSelectionModel(allowCollections: true, allowEntrySelection: true))
    }
}
