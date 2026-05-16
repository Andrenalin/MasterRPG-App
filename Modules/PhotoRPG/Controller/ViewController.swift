// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    public let fileImporterViewType: FileImporterViewType = .custom
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    @MainActor public func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView {
        AnyView(InlineImporterView(itemId: itemId, preopen: preopen, layoutDown: layoutDown).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }
}

// MARK: - External Views

public extension ViewController {
    @MainActor func dropSelectionView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
    
    @ViewBuilder @MainActor func thumbnailRow(root: PhotoRootModel, for itemId: UUID, listDisplayModel: ListDisplayModel) -> some View {
        if let model = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
            ThumbnailRowPhotoView(cacheController: cacheController, model: model, listDisplayModel: listDisplayModel)
        }
    }
    
    @ViewBuilder @MainActor func photoRow(root: PhotoRootModel, for itemId: UUID) -> some View {
        if let model = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
            CachePhotoView(cacheController: cacheController, model: model, highResolution: true)
        }
    }

    @ViewBuilder @MainActor func carouselPhotos(root: PhotoRootModel, photoSelection: ItemSelectionModel) -> some View {
        CarouselPhotoView(photoIds: photoSelection, selection: GroupItemSelectionModel(selectedItem: nil))
    }
}

// MARK: - List View

public extension ViewController {
    @MainActor func gameListView(root: PhotoRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }
    
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func gameViewer(root: PhotoRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), configuration: ViewerConfiguration(isGame: true))
    }

    @MainActor func viewer(root: PhotoRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: itemId), configuration: configuration, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: PhotoRootModel, selection: WindowItemSelection) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: selection.itemId), configuration: ViewerConfiguration(closeButton: false))
    }
}

// MARK: - Special Viewers

public extension ViewController {    
    @MainActor func mapImage(root: PhotoRootModel, for itemId: UUID?, size: CGSize, color: Color) -> some View {
        AsyncThumbnail(model: root.gameController.gameItem(for: itemId ?? UUID()), size: size, color: color)
            .environment(root)
    }

    @MainActor func photoDetailView(root: PhotoRootModel, for itemId: UUID?, size: CGSize, contentMode: ContentMode = .fit) -> some View {
        let id = itemId ?? UUID()
        let model = root.itemController.itemOrEmpty(for: id)
        return AsyncImageViewer(model: model, size: size, contentMode: contentMode, toolBarModel: nil)
    }

    #if os(visionOS)
    func imageSpaceView() -> some View {
        ImageSpaceView()
    }
    #endif
}
