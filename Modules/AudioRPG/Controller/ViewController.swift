// @copyright André Trettin

import CoreRPG
import Observation
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .custom
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    @MainActor public func sharingView(for itemId: UUID) -> AnyView {
        AnyView(SharingActionView(itemId: itemId))
    }
}

// MARK: - New Views

public extension ViewController {
    @MainActor
    func linkWindow(isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(ItemSelectionModel())
    }
        
    @MainActor func selectionView(model: ItemSelectionModel) -> some View {
        LinkRootView(type: .selection)
            .environment(model)
    }
}

// MARK: - Edit

public extension ViewController {
    @MainActor
    func detailEditor(root: AudioRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        AudioDetailPlayerView(item: item)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID(uuidString: "2942C8E2-A5E9-432F-8E10-92EEC7BC344C")!

    @MainActor
    func gameView(root: AudioRootModel, select: Bool = false) -> some View {
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

// MARK: Selection

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID(uuidString: "CE494ADC-7509-4F3E-96FF-9EC390F225C7")!

    @MainActor
    func viewSelect(root: AudioRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
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
    func rowView(root: AudioRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        AudioRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
}

// MARK: - Others

public extension ViewController {
    @MainActor
    func audioWindow(root: AudioRootModel, selection: ItemSelection) -> some View {
        viewAudioPlayer(root: root, with: selection.itemId)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    @MainActor
    func viewAudioPlayer(root: AudioRootModel, with id: UUID?) -> some View {
        root.gameController.play(id: id, shouldPlay: true)
        return AudioPlayerView()
            .environment(root)
    }

    func viewVolume(root: AudioRootModel, alignment: Alignment) -> some View {
        PlayerVolumeView(root: root, alignment: alignment)
    }
}
