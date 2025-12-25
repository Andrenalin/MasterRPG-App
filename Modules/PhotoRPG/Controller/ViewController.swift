// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    public let fileImporterViewType: FileImporterViewType = .custom
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    @MainActor public func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView {
        AnyView(PhotoInlineImporterView(itemId: itemId, preopen: preopen, layoutDown: layoutDown))
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func dropSelectionView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
    
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }
    
    @ViewBuilder @MainActor func thumbnailRow(root: PhotoRootModel, for itemId: UUID) -> some View {
        if let model = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
            ThumbnailRowPhotoView(cacheController: cacheController, model: model)
                .environment(root.editController.cacheItemListModel)
                .environment(root.listDisplayModel)
        }
    }

    @ViewBuilder @MainActor func photoRow(root: PhotoRootModel, for itemId: UUID) -> some View {
        if let model = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
            CachePhotoView(cacheController: cacheController, model: model, highResolution: true)
                .environment(root.editController.cacheItemListModel)
        }
    }

    @MainActor func inlineViewer(root: PhotoRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: PhotoRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model)
    }
    
    @MainActor func gameView(root: PhotoRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
    
    @MainActor
    func gamePhotoView(root: PhotoRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), isGame: true)
            .environment(root)
    }
}

// MARK: - Edit

public extension ViewController {
    @MainActor func onMapView(root: PhotoRootModel, photoId: UUID?, color: Color, size: CGSize, isDragging: Bool, isSelected: Bool) -> some View {
        OnMapPin(model: root.itemController.itemOrEmpty(for: photoId ?? UUID()), color: color, size: size, isDragging: isDragging, isSelected: isSelected)
            .environment(root)
    }
    
    @MainActor func mapImage(root: PhotoRootModel, for itemId: UUID?, size: CGSize, color: Color) -> some View {
        AsyncThumbnail(model: root.gameController.gameItem(for: itemId ?? UUID()), size: size, color: color)
            .environment(root)
    }

    @MainActor func photoDetailView(root: PhotoRootModel, for itemId: UUID?, useGame: Bool, size: CGSize, contentMode: ContentMode = .fit) -> some View {
        let id = itemId ?? UUID()
        let model = useGame ? root.gameController.gameItem(for: id) : root.itemController.itemOrEmpty(for: id)
        return AsyncPhotoViewer(model: model, size: size, contentMode: contentMode)
            .environment(root)
    }
}
