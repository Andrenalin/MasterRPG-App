// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
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

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?, isShareable: Bool) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination, sourceModel: sourceModel, isShareable: isShareable).equatable())
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
    @MainActor func gameViewer(
        root: PhotoRootModel,
        trailingViewportReservation: CGFloat = 0,
        bottomViewportReservation: CGFloat = 0
    ) -> some View {
        ViewerRootView(
            model: root.gameController.currentItem(),
            configuration: ViewerConfiguration(isGame: true),
            trailingViewportReservation: trailingViewportReservation,
            bottomViewportReservation: bottomViewportReservation
        )
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
        AsyncThumbnail(itemId: itemId, size: size, color: color)
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

    /// Cross-module entry point: the photo `model` selects, converted to spatial 3D and fitted
    /// into its window, as the photo window shows it.
    @MainActor func spatialPhotoView(root: PhotoRootModel, model: ImagePresentationModel) -> some View {
        ImagePresentationView(model: model)
            .environment(root)
    }

    /// The spatial photo with `foreground` in front of it, over the photo's whole area, such as
    /// a weather. It stays in front of the photo's depth as the conversion runs.
    @MainActor func spatialPhotoView<Foreground: View>(
        root: PhotoRootModel,
        model: ImagePresentationModel,
        @ViewBuilder foreground: () -> Foreground
    ) -> some View {
        ImagePresentationView(model: model, foreground: foreground())
            .environment(root)
    }

    /// The photo window's ornament for `model`: switches between 2D and 3D.
    @MainActor func spatialPhotoOrnament(model: ImagePresentationModel) -> some View {
        OrnamentsView(model: model)
    }
    #endif
}
