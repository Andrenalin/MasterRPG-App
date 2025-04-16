// @copyright André Trettin

import AndrenalinKit
import SwiftUI

public struct ViewController: Sendable {
    weak var root: AdventureRoot!
}

// MARK: - Viewer

public extension ViewController {
    //@MainActor
    func viewMinimum(with id: UUID?) -> some View {
        MinimumRow(itemId: id ?? UUID())
            .environment(root)
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor
    private static let gameTabId = UUID()
    
    @MainActor
    func gameView(focusedIds: [UUID], openAction: ((NetworkModules) -> Void)? = nil) -> some View {
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
    func overlayRootView(adventureId: UUID) -> some View {
        gameView(focusedIds: [adventureId], openAction: nil)
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
    
    @MainActor
    func adventureWindow(selection: ItemSelection) -> some View {
        AdventureSheet(model: root.itemController.itemOrEmpty(for: selection.itemId), showImage: true, dismissAction: nil)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }
}

// MARK: Selection

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
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
    func selectForScan(ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
        viewSelect {
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
