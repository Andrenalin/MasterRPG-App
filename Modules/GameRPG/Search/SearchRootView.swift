// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SearchRootView: View {
    let root: GameRoot
    let navigator: Navigator

    var body: some View {
        SearchListView(root: root, searchController: root.searchController)
            .modifier(CompactNavigationModifier(
                root: root,
                navigator: navigator,
                model: root.searchController.model
            ))
    }
}

// MARK: - Navigation Modifier

private struct CompactNavigationModifier: ViewModifier {
    let root: GameRoot
    let navigator: Navigator
    @Bindable var model: GlobalSearchModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    func body(content: Content) -> some View {
        if appSizeModel.mode == .compact {
            content
                .navigationDestination(item: $model.selection) { _ in
                    SearchDetailView(root: root, navigator: navigator)
                }
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    SearchRootView(root: GameRoot.preview, navigator: Navigator(configuration: NavigationConfiguration()))
}
