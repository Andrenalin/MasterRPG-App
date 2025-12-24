// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .none
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source).equatable())
    }
}

// MARK: - External Views

extension ViewController {
    @MainActor func photoSelection(root: WeatherRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.photoRoot.viewController.dropSelectionView(model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func inlineViewer(root: WeatherRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: WeatherRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, windowMode: true)
    }
    
    @MainActor func gameView(root: WeatherRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

// MARK: - old

public extension ViewController {
    func gameWeatherView(root: WeatherRootModel) -> some View {
        RootGame()
            .environment(root)
    }

    @MainActor @ViewBuilder
    func photo(root: WeatherRootModel, for itemId: UUID, useGame: Bool, size: CGSize) -> some View {
        root.photoRoot.viewController.photoDetailView(root: root.photoRoot, for: itemId, useGame: useGame, size: size, contentMode: .fill)
    }
}
