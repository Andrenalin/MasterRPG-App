// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: - New Views

public extension ViewController {
    @MainActor
    func linkWindow(root: AudioRoot, isInspector: Bool = false) -> some View {
        Text("")
//        LinkRootView(type: isInspector ? .inspector : .window)
//            .environment(root)
    }
    
    @MainActor
    func windowViewer(root: AudioRoot, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return NavigationStack {
//            SpaceExternalHeader(editController: root.editController(type: .main), model: model, isModal: true)
        }
        .ignoresSafeArea()
        .navigationTitle(model.name)
        .environment(root)
    }

    @MainActor
    func inlineViewer(root: AudioRoot, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return Text("")
//        return SpaceExternalHeader(editController: root.editController(type: .main), model: model, isModal: true)
            .environment(root)
    }
    
    @MainActor func selectionView(root: AudioRoot, model: ItemSelectionModel) -> some View {
        Text("")
//        LinkRootView(type: .selection)
            .environment(root)
    }
}

// MARK: - Edit

public extension ViewController {
    @MainActor
    func detailEditor(root: AudioRoot, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        AudioDetailPlayerView(item: item)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID(uuidString: "2942C8E2-A5E9-432F-8E10-92EEC7BC344C")!

    @MainActor
    func gameView(root: AudioRoot, select: Bool = false) -> some View {
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
    func linkWindow(root: AudioRoot) -> some View {
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
    func viewSelect(root: AudioRoot, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
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
    func rowView(root: AudioRoot, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        AudioRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
}

// MARK: - Others

public extension ViewController {
    @MainActor
    func audioWindow(root: AudioRoot, selection: ItemSelection) -> some View {
        viewAudioPlayer(root: root, with: selection.itemId)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    @MainActor
    func viewAudioPlayer(root: AudioRoot, with id: UUID?) -> some View {
        root.gameController.play(id: id, shouldPlay: true)
        return AudioPlayerView()
            .environment(root)
    }

    func viewVolume(root: AudioRoot, alignment: Alignment) -> some View {
        PlayerVolumeView(root: root, alignment: alignment)
    }
}
