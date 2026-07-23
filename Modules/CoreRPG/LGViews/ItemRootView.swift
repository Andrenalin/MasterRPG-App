// @copyright André Trettin

import SwiftUI

public struct ItemRootView: View {
    public init(root: ItemRootController) {
        self.root = root
    }
    
    let root: ItemRootController
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ItemRootListView(root: root)
            .environment(root)
            .moduleTint(root.configurable.module)
            .task {
                root.navigationModel.navigator = navigator
            }
    }
}

#Preview("Item Root") {
    ItemRootView(root: ItemRootController.fake)
}
