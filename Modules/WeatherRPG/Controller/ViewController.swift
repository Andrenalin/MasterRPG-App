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
        return ViewerRootView(model: model)
    }
}

// MARK: - old

public extension ViewController {
    @MainActor
    func detailEditor(root: WeatherRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        WeatherDetailViewer(item: item)
            .environment(root)
    }

    func gameWeatherView(root: WeatherRootModel) -> some View {
        RootGame()
            .environment(root)
    }
    
    @MainActor
    func weatherWindow(root: WeatherRootModel, selection: ItemSelection) -> some View {
        WeatherWindow(selection: selection)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(root: WeatherRootModel, select: Bool = false) -> some View {
        if select == true, let id = root.gameController.gameModel.currentItemId {
            let item = root.gameController.gameItem(for: id)
            if item.displayState == 0 {
                let model = ItemRowModel(itemId: id, typeId: root.itemController.itemDataModel.networkModule)
                let _ = root.listController(tabId: ViewController.gameTabId, focus: model)
            }
        }
        return RootNaviList(root: root, tabId: ViewController.gameTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false, disableSelection: true)
            .environment(root)
    }
}

// MARK: Selection

extension ViewController {
    @MainActor @ViewBuilder
    func photo(root: WeatherRootModel, for itemId: UUID, useGame: Bool, size: CGSize) -> some View {
        root.photoRoot.viewController.photoDetailView(root: root.photoRoot, for: itemId, useGame: useGame, size: size, contentMode: .fill)
    }
}

// MARK: Viewer

public extension ViewController {
    func rowView(root: WeatherRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        WeatherRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
    
    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(root: WeatherRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = true, focus: UUID? = nil, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: isGroupHidden, focus: focus, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }
}
