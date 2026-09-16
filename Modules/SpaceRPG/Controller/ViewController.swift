// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public let fileImporterViewType: FileImporterViewType = .custom
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    public var skipsHeaderEditorOnCreate: Bool { true }

    @MainActor public func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView {
        AnyView(InlineImporterView(itemId: itemId, preopen: preopen, layoutDown: layoutDown).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination, sourceModel: sourceModel).equatable())
    }
}

// MARK: - List View

public extension ViewController {
    @MainActor func gameListView(root: SpaceRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }
    
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor @ViewBuilder func gameViewer(root: SpaceRootModel) -> some View {
        if let currentItemId = root.gameController.gameModel.currentItemId {
#if os(tvOS)
            SpaceQuickLook(root: root, item: ItemSelection(itemId: currentItemId, entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
#elseif os(visionOS)
            SpaceQuickLook(root: root, item: ItemSelection(itemId: currentItemId, entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
#else
            SpaceViewer(root: root, id: currentItemId, isModal: false)
                .padding()
#endif
        }
    }

    @MainActor func viewer(root: SpaceRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: itemId), configuration: configuration, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: SpaceRootModel, selection: WindowItemSelection) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: selection.itemId), configuration: ViewerConfiguration(closeButton: false, isGame: true))
    }
}

// MARK: - Game

public extension ViewController {
    
#if os(visionOS)
    @MainActor @ViewBuilder func spaceImmersionWindow(root: SpaceRootModel, id: UUID, defaultSize: Size3D) -> some View {
        SpaceViewer(root: root, id: id, isModal: false, isImmersiveSpace: true)
            .id(id)
            // Outside `.id(id)` deliberately: `openSpaceViewer` can replace
            // which item this shows (see `ScenesManager.currentSpaceViewerItemId`)
            // by changing `id`, which tears down and recreates `SpaceViewer`
            // entirely. Tracking the immersive space's lifecycle *inside*
            // `SpaceViewer` (as it used to be) meant every replace fired a
            // spurious onDisappear→onAppear — briefly reporting the space
            // closed and reopened on every item swap, corrupting
            // `ScenesManager`'s state machine (e.g. leaving the close button
            // unable to dismiss after a second object replaced the first).
            // Applied here, on the stable call site that only ever
            // constructs the one true immersive instance, it fires once for
            // the space's actual open/close — not per item.
            .immersiveSpaceTracker()
    }
#endif
}
