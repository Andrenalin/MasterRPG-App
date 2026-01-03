// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public let fileImporterViewType: FileImporterViewType = .custom
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    @MainActor public func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView {
        AnyView(InlineImporterView(itemId: itemId, preopen: preopen, layoutDown: layoutDown).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source).equatable())
    }
}

// MARK: - List View

public extension ViewController {
    @MainActor func gameListView(root: SpaceRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
    
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor @ViewBuilder func gameViewer(root: SpaceRootModel) -> some View {
#if os(tvOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
#elseif os(visionOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
#else
        SpaceViewer(root: root, id: root.gameController.gameModel.currentItemId ?? UUID(), isModal: false)
            .padding()
#endif
    }

    @MainActor func inlineViewer(root: SpaceRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: id), dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: SpaceRootModel, selection: WindowItemSelection) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: selection.itemId))
    }
}

// MARK: - Game

public extension ViewController {
    
#if os(visionOS)
    @MainActor @ViewBuilder func spaceImmersionWindow(root: SpaceRootModel, id: UUID, defaultSize: Size3D) -> some View {
        SpaceViewer(root: root, id: id, isModal: false)
    }
#endif
}
