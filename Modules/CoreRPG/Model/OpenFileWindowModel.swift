// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class OpenFileWindowModel {
    public init() {}

    public init(windowId: String, canShow: Bool = false, route: @escaping (UUID) -> any NavigationDestination) {
        self.windowId = windowId
        self.canShow = canShow
        self.route = route
    }
    
    public var showItem: Bool = false
    public var itemId: UUID = UUID()
    public var entryId: UUID?
    public var url: URL?
    public var canShow: Bool = false
    
    public var windowId: String? = nil
    public var route: ((UUID) -> any NavigationDestination)?
    
    public var enabled: Bool {
        canShow || url != nil
    }
}

public extension View {
    /// The "open file" overlay every module's `DetailFolderListView` shows above
    /// its content whenever `openFileWindowModel.showItem` is set: presents
    /// `viewer`, and dismisses by resetting `showItem` back to `false`. Each
    /// module's own `viewController.viewer(root:itemId:configuration:dismissAction:)`
    /// call still varies (different `ViewerConfiguration`/extra parameters), so
    /// only that surrounding "check/extract/dismiss" wiring is shared here — not
    /// the viewer call itself.
    @ViewBuilder
    func openFileWindowOverlay<Viewer: View>(
        _ openFileWindowModel: OpenFileWindowModel,
        @ViewBuilder viewer: (UUID, @escaping () -> Void) -> Viewer
    ) -> some View {
        overlay {
            if openFileWindowModel.showItem {
                viewer(openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
    }
}
