// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

public struct ViewController {
    weak var root: WeatherRoot!
}

public extension ViewController {
    @MainActor
    func detailEditor(for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        WeatherDetailViewer(item: item)
            .environment(root)
    }

    func gameWeatherView() -> some View {
        RootGame()
            .environment(root)
    }
    
    @MainActor
    func weatherWindow(selection: ItemSelection) -> some View {
        WeatherWindow(selection: selection)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(select: Bool = false) -> some View {
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

// MARK: Links

public extension ViewController {
    @MainActor
    private static let linkTabId = UUID()

    @MainActor
    func linkWindow() -> some View {
        RootNaviList(root: root, tabId: ViewController.linkTabId)
            .itemSplitViewSizeMode(.small)
            .itemListConfiguration(canAdd: false)
            .itemListChildrenConfiguration(canNavigate: false)
            .focusedSceneValue(\.selectedModule, .constant(root.itemController.itemDataModel.networkModule))
            .environment(root)
            .environment(SelectionSheetLinkModel())
    }
}

// MARK: Selection

extension ViewController {
    @MainActor @ViewBuilder
    func photo(for itemId: UUID, useGame: Bool) -> some View {
        root.photoRoot.viewController.photoView(for: root.itemController.itemOrEmpty(for: itemId).photoId, useGame: useGame) { image, degrees in
            Image(akImage: image)
                .resizable()
                .rotationEffect(Angle(degrees: degrees))
                .id(root.itemController.itemOrEmpty(for: itemId).photoId)
        }
    }
}

// MARK: Viewer

public extension ViewController {
    func rowView(item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        WeatherRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
    
    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = true, focus: UUID? = nil, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: isGroupHidden, focus: focus, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }
}
