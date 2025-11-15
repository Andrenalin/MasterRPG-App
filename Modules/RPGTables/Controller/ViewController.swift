// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGDie

public struct ViewController {
    weak var root: TableRoot!
}

public extension ViewController {
    @MainActor
    func detailEditor(for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        TableDetailSheet(item: item)
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
    
    @MainActor
    func generatorEditorWindow() -> some View {
        GeneratorWindow(root: root)
            .environment(root)
    }

    @MainActor
    private static let linkTabId = UUID()

    @MainActor
    func linkWindow() -> some View {
        RootNaviList(root: root, tabId: ViewController.linkTabId)
            .itemSplitViewSizeMode(.small)
            .itemListConfiguration(canAdd: false)
            .itemListChildrenConfiguration(canNavigate: false)
            .focusedSceneValue(\.selectedModule, .constant(.table))
            .environment(root)
            .environment(SelectionSheetLinkModel())
    }

    @MainActor
    func tableSheetWindow(selection: ItemSelection) -> some View {
        TableSheet(model: root.itemController.itemOrEmpty(for: selection.itemId), showTopImage: true, dismissAction: nil)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = true, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: isGroupHidden, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }

    func rowView(item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        TableRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
    
    @MainActor
    func generatorRow(controllable: GeneratorControllable?, item: ItemRowTreeModel) -> some View {
        let controller = controllable as? GeneratorController
        let model = controller?.genDataModel.itemDataModel.itemData[item.model.itemId] as? TableModel ?? .empty
        return TableRowModel(item: item, model: model, isSelected: false, cacheItemListModel: CacheItemListModel())
            .environment(root)
            .environment(\.showGame, false)
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor
    func gameTableView() -> some View {
        TableGameSheet()
            .environment(root)
            .environment(\.showGame, true)
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

public extension ViewController {
    @MainActor
    func viewGenerator(with id: UUID, dismissAction: @escaping (UUID?) -> Void) -> some View {
        GeneratorRoot(generatorController: root.generatorController(rootItem: ItemRowModel(itemId: id, typeId: .table)), item: .constant(nil))
    }
}

// MARK: - Dice

extension ViewController {
    @MainActor @ViewBuilder
    func rowDiceView(for id: UUID?, cacheItemListModel: CacheItemListModel) -> some View {
        if let id {
            root.diceRoot.viewController.viewRow(root: root.diceRoot, item: ItemRowTreeModel(itemId: id, typeId: .table), isSelected: false, cacheItemListModel: cacheItemListModel)
        } else {
            EmptyView()
        }
    }

    @MainActor @ViewBuilder
    func diceView(for id: UUID?, from itemId: UUID) -> some View {
        if let id {
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: id, for: ResultCategory(id: itemId, module: root.itemController.itemDataModel.networkModule))
        } else {
            EmptyView()
        }
    }
}
