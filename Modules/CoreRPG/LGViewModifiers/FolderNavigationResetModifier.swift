// @copyright André Trettin

import SwiftUI

public extension View {
    /// Attaches a task that resets the folder navigation state when an iPad-sized
    /// (regular) layout is active and the selected item changes.
    ///
    /// The `@Environment(AppWindowSizeModel.self)` dependency is owned by this
    /// modifier's own tracking context — it does NOT propagate to the applying
    /// view, preventing spurious `@self changed` re-renders on layout changes.
    func folderNavigationResetTask(
        navigationModel: ModuleNavigationModel,
        itemId: UUID
    ) -> some View {
        modifier(FolderNavigationResetModifier(navigationModel: navigationModel, itemId: itemId))
    }
}

private struct FolderNavigationResetModifier: ViewModifier {
    let navigationModel: ModuleNavigationModel
    let itemId: UUID

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    func body(content: Content) -> some View {
        content
            .task(id: itemId) {
                guard appSizeModel.mode == .regular else { return }
                navigationModel.folderItems <=> []
                if !navigationModel.folderModels.isEmpty {
                    navigationModel.folderModels = [:]
                }
            }
    }
}
