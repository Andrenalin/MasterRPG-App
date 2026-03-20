// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct SearchRootView: View {
    public init(root: GameRoot) {
        self.root = root
    }

    let root: GameRoot

    @Environment(\.appSizeMode) private var appSizeMode

    public var body: some View {
        @Bindable var model = root.searchController.model

        SearchListView(root: root, searchController: root.searchController)
            .modifier(CompactNavigationModifier(
                isCompact: appSizeMode == .compact,
                selection: $model.selection,
                root: root,
                searchController: root.searchController
            ))
    }
}

// MARK: - Navigation Modifier

private struct CompactNavigationModifier: ViewModifier {
    let isCompact: Bool
    @Binding var selection: SearchResult?
    let root: GameRoot
    let searchController: SearchController

    func body(content: Content) -> some View {
        if isCompact {
            content
                .navigationDestination(item: $selection) { _ in
                    SearchDetailView(root: root, searchController: searchController)
                }
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    SearchRootView(root: GameRoot.preview)
}
