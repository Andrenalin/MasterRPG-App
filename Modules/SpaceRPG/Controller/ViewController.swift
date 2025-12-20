// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: - New Views

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func inlineViewer(root: SpaceRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, dismissAction: dismissAction)
    }

    @MainActor func windowViewer(root: SpaceRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, windowMode: true)
    }
    
    @MainActor func gameView(root: SpaceRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

// MARK: - Edit

public extension ViewController {
    @MainActor
    func detailEditor(root: SpaceRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        SpaceDetailViewer(item: item)
            .environment(root)
    }
}

// MARK: - Game
public extension ViewController {
    @MainActor @ViewBuilder
    func gameSpaceView(root: SpaceRootModel) -> some View {
#if os(tvOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .environment(SelectionSheetLinkModel())
#elseif os(visionOS)
        SpaceQuickLook(root: root, item: ItemSelection(itemId: root.gameController.gameModel.currentItemId ?? UUID(), entryId: nil), startLoading: true, gameMode: true, dismiss: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .environment(SelectionSheetLinkModel())
#else
        SpaceViewer(root: root, id: root.gameController.gameModel.currentItemId ?? UUID(), isModal: false)
            .padding()
#endif
    }
}

// MARK: - Selection

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID()
    
    @MainActor
    func viewSelect(root: SpaceRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: true, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        
//        return LinkRootView(type: .selection)
//            .environment(root)
//            .environment(listController.model)

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
    
#if os(visionOS)
    @MainActor @ViewBuilder
    func spaceImmersionWindow(root: SpaceRootModel, id: UUID, defaultSize: Size3D) -> some View {
        SpaceViewer(root: root, id: id, isModal: false)
    }
#endif
    
    @MainActor
    func spaceWindow(root: SpaceRootModel, selection: ItemSelection) -> some View {
        SpaceQuickLook(root: root, item: selection, startLoading: true, gameMode: false, dismiss: nil)
    }
}

// MARK: - Viewer

public extension ViewController {
    func rowView(root: SpaceRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        SpaceRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
}
