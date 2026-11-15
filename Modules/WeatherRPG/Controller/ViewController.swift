// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

public struct ViewController: Sendable {
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }

    @MainActor public func thumbnailRowView(for model: any ItemDataAccessible) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: model.id, item: model as? WeatherModel).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination, sourceModel: sourceModel).equatable())
    }
}

// MARK: - External Views

extension ViewController {
    @MainActor func photoSelection(root: WeatherRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.photoRoot.viewController.dropSelectionView(model: selectionModel)
    }
}

// MARK: - List View

public extension ViewController {
    @MainActor func gameListView(root: WeatherRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }
    
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func gameViewer(root: WeatherRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), configuration: ViewerConfiguration(isGame: true))
    }

    /// Cross-module entry point: a weather of the running game in a popover on the game map
    /// (GameRPG hands it to MapRPG). Brings its own environment: a visionOS table attachment
    /// does not inherit the app's, and the weather's photo is drawn by PhotoRPG.
    @MainActor func gamePopoverViewer(root: WeatherRootModel, itemId: UUID) -> some View {
        WeatherPopoverViewer(model: root.gameController.gameItem(for: itemId))
            .environment(root)
            .environment(root.editController.cacheItemListModel)
            .environment(root.photoRoot)
    }
    
#if os(visionOS)
    /// The visionOS weather window's content: the shown weather's photo in spatial 3D with the
    /// weather in front of it.
    @MainActor func weatherSpaceView(root: WeatherRootModel) -> some View {
        WeatherSpaceView()
            .environment(root)
            .environment(root.editController.cacheItemListModel)
            .environment(root.photoRoot)
    }
#endif

    @MainActor func viewer(root: WeatherRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: itemId), configuration: configuration, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: WeatherRootModel, selection: WindowItemSelection) -> some View {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: selection.itemId), configuration: ViewerConfiguration(closeButton: false))
    }
}
