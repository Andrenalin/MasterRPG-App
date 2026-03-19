// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct SearchRootView: View {
    public init(root: GameRoot, searchText: String = "") {
        self.root = root
    }

    let root: GameRoot
    
    @Environment(\.appSizeMode) private var appSizeMode

    public var body: some View {
        if appSizeMode == .compact {
            @Bindable var model = root.searchController.model
            SearchListView(root: root, searchController: root.searchController)
                .navigationDestination(item: $model.selection) { _ in
                    SearchDetailView(root: root, searchController: root.searchController)
                }
        } else {
            SearchListView(root: root, searchController: root.searchController)
            #if !os(tvOS)
                .listStyle(.sidebar)
            #endif
        }
    }
}

// MARK: - Preview

#Preview {
    SearchRootView(root: GameRoot.preview, searchText: "T")
}
