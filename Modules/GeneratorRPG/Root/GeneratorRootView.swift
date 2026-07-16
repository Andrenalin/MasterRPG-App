// @copyright André Trettin


import CoreRPG
import SwiftUI

struct GeneratorRootView: View {
    @Environment(GeneratorRootModel.self) private var root
    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root, restoresState: restoresState)
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        GeneratorRootView(restoresState: false)
    }
}
