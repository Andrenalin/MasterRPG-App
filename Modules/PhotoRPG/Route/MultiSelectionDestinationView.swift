// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MultiSelectionDestinationView: View {
    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: root.itemSelectionModel)
    }
}

#Preview(traits: .mockData) {
    MultiSelectionDestinationView()
        .environment(ItemSelectionModel(isSingleSelection: false))
}
