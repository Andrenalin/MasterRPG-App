// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

public struct ViewController {
    weak var root: SpaceRoot!
}

// MARK: - Edit

public extension ViewController {
    @MainActor
    func detailEditor(for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        SpaceDetailViewer(item: item)
            .environment(root)
    }
}

// MARK: - Game
public extension ViewController {
    @MainActor @ViewBuilder
    func gameSpaceView() -> some View {
#if os(tvOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .environment(SelectionSheetLinkModel())
#elseif os(visionOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .environment(SelectionSheetLinkModel())
#else
        SpaceViewer(root: root, id: root.gameController.gameModel.currentItemId ?? UUID())
            .padding()
#endif
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

// MARK: - Selection

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID()
    
    @MainActor
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: true, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }
}

// MARK: - Window

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
    
#if os(visionOS)
    @MainActor @ViewBuilder
    func spaceImmersionWindow(id: UUID, defaultSize: Size3D) -> some View {
        SpaceViewer(root: root, id: id)
    }
#endif
    
    @MainActor
    func spaceWindow(selection: ItemSelection) -> some View {
        SpaceQuickLook(root: root, item: selection, startLoading: true, gameMode: false, dismiss: nil)
    }
}

// MARK: - Viewer

public extension ViewController {
    func rowView(item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        SpaceRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
}
