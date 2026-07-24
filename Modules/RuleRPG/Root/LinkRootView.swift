// @copyright André Trettin

import CoreRPG
import SwiftUI

struct LinkRootView: View {
    let type: LinkRootType
    let itemSelectionModel: ItemSelectionModel

    @Environment(RuleRootModel.self) private var root

    var body: some View {
        LinkItemRootView(
            root: root.rootController,
            type: type,
            itemSelectionModel: itemSelectionModel
        )
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        LinkRootView(
            type: .inspector,
            itemSelectionModel: ItemSelectionModel(
                allowCollections: true,
                allowEntrySelection: true
            )
        )
    }
}
