// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: - New Views

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func inlineViewer(root: SpaceRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, dismissAction: dismissAction)
    }

    @MainActor func windowViewer(root: SpaceRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, windowMode: true)
    }
    
    @MainActor func gameView(root: SpaceRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor @ViewBuilder
    func gameSpaceView(root: SpaceRootModel) -> some View {
#if os(tvOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .environment(SelectionSheetLinkModel())
#elseif os(visionOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .environment(SelectionSheetLinkModel())
#else
        SpaceViewer(root: root, id: root.gameController.gameModel.currentItemId ?? UUID(), isModal: false)
            .padding()
#endif
    }
    
#if os(visionOS)
    @MainActor @ViewBuilder
    func spaceImmersionWindow(root: SpaceRootModel, id: UUID, defaultSize: Size3D) -> some View {
        SpaceViewer(root: root, id: id, isModal: false)
    }
#endif
}
