// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MultiSelectionDestinationView: View {
    @Environment(PhotoRootModel.self) private var root
    @Environment(ItemSelectionModel.self) private var itemSelectionModel

    var body: some View {
        LinkRootView(type: .selection, itemSelectionModel: itemSelectionModel)
    }
}

#Preview(traits: .mockData) {
    MultiSelectionDestinationView()
        .environment(ItemSelectionModel(isSingleSelection: false))
}
