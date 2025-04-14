// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

public struct ViewController {
    weak var root: AudioRoot!
}

public extension ViewController {
    @MainActor
    func detailEditor(for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        AudioDetailPlayerView(item: item)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID(uuidString: "2942C8E2-A5E9-432F-8E10-92EEC7BC344C")!

    @MainActor
    func gameView(select: Bool = false) -> some View {
        var model: ItemRowModel? = nil
        if select == true, let id = root.gameController.gameModel.currentItemId {
            let item = root.gameController.gameItem(for: id)
            if item.displayState == 0 {
                model = ItemRowModel(itemId: id, typeId: root.itemController.itemDataModel.networkModule)
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
    private static let linkTabId = UUID(uuidString: "939EE771-278F-4332-902F-7E9C93A07A24")!

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

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID(uuidString: "CE494ADC-7509-4F3E-96FF-9EC390F225C7")!

    @MainActor
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: false, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }
}

// MARK: Viewer

public extension ViewController {
    func rowView(item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        AudioRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
}

// MARK: - Others

public extension ViewController {
    @MainActor
    func audioWindow(selection: ItemSelection) -> some View {
        viewAudioPlayer(with: selection.itemId)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    @MainActor
    func viewAudioPlayer(with id: UUID?) -> some View {
        root.gameController.play(id: id, shouldPlay: true)
        return AudioPlayerView()
            .environment(root)
    }

    func viewVolume(alignment: Alignment) -> some View {
        PlayerVolumeView(root: root, alignment: alignment)
    }
}
