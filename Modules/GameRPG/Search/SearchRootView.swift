// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct SearchRootView: View {
    public init(root: GameRoot, searchText: String = "") {
        self.root = root
        self._searchController = State(initialValue: SearchController(root: root, searchText: searchText))
    }

    let root: GameRoot
    
    @Environment(\.appSizeMode) private var appSizeMode
    @State private var searchController: SearchController

    public var body: some View {
        if appSizeMode == .compact {
            @Bindable var model = searchController.model
            NavigationStack {
                SearchListView(root: root, searchController: searchController)
                    .navigationDestination(item: $model.selection) { _ in
                        SearchDetailView(root: root, searchController: searchController)
                    }
            }
        } else {
            NavigationSplitView {
                SearchListView(root: root, searchController: searchController)
                    .listStyle(.sidebar)
            } detail: {
                SearchDetailView(root: root, searchController: searchController)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SearchRootView(root: GameRoot.preview, searchText: "T")
}
