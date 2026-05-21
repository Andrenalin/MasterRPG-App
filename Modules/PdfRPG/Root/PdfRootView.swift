// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PdfRootView: View {
    @Environment(PdfRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                ItemStateRestorationView<PdfRoute, PdfRootModel>(root: root, keyPrefix: "Pdf")
            }
            .onNavigationReceive { (route: PdfRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        PdfRootView()
    }
}
