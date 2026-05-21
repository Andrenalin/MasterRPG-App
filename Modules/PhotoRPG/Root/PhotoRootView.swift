// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PhotoRootView: View {
    @Environment(PhotoRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .background {
                ItemStateRestorationView<PhotoRoute, PhotoRootModel>(root: root, keyPrefix: "Photo")
            }
            .onNavigationReceive { (route: PhotoRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        PhotoRootView()
    }
}
