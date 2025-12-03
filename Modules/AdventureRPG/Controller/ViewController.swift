// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .item
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }
}

// MARK: External Views

extension ViewController {
    @MainActor
    func diceSelection(root: AdventureRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.selectionView(root: root.diceRoot, model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkWindow(isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(ItemSelectionModel())
    }
    
    @MainActor func windowViewer(root: AdventureRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return AdventureSheet(model: model, dismissAction: nil)
    }

    @MainActor func inlineViewer(root: AdventureRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return AdventureSheet(model: model, dismissAction: dismissAction)
    }
    
    @MainActor func selectionView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
}

// MARK: - Viewer

public extension ViewController {
    //@MainActor
    func viewMinimum(root: AdventureRootModel, with id: UUID?) -> some View {
        MinimumRow(itemId: id ?? UUID())
            .environment(root)
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor
    private static let gameTabId = UUID()
    
    @MainActor
    func gameView(root: AdventureRootModel, focusedIds: [UUID], openAction: ((NetworkModules) -> Void)? = nil) -> some View {
        if let id = focusedIds.first {
            let model = ItemRowModel(itemId: id, typeId: root.itemController.itemDataModel.networkModule)
            let _ = root.listController(tabId: ViewController.gameTabId, focus: model)
        }
        return RootNaviList(root: root, tabId: ViewController.gameTabId, openAction: openAction)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false, disableSelection: true)
            .environment(root)
    }

    @MainActor
    func overlayRootView(root: AdventureRootModel, adventureId: UUID) -> some View {
        gameView(root: root, focusedIds: [adventureId], openAction: nil)
    }
}

// MARK: Selection

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(root: AdventureRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: isGroupHidden, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
            .environment(SelectionSheetLinkModel(selection: false))
    }
}

// MARK: Links

public extension ViewController {
    @MainActor 
    func selectForScan(root: AdventureRootModel, ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(root: root) {
            if let links = ids.wrappedValue {
                return links.map { ItemRowModel(itemId: $0, entryId: entryId?.wrappedValue, typeId: root.itemController.itemDataModel.networkModule) }
            } else {
                return []
            }
        } toggleSelection: { selection, _ in
            if entryOnly {
                if ids.wrappedValue?.first == selection.itemId,
                   entryId?.wrappedValue == selection.entryId
                {
                    ids.wrappedValue = nil
                    entryId?.wrappedValue = nil
                } else {
                    ids.wrappedValue = [selection.itemId]
                    entryId?.wrappedValue = selection.entryId
                }
            } else {
                if let index = ids.wrappedValue?.firstIndex(of: selection.itemId) {
                    ids.wrappedValue?.remove(at: index)
                } else {
                    if ids.wrappedValue == nil {
                        ids.wrappedValue = []
                    }
                    ids.wrappedValue?.append(selection.itemId)
                }
            }
        } dismissAction: {
            dismissAction()
        }
    }
}
