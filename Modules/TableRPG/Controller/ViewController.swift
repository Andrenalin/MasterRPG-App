// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .item
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: itemId))
    }
}

// MARK: External Views

extension ViewController {
    @MainActor
    func diceSelection(root: TableRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.selectionView(root: root.diceRoot, model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkWindow(isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
    }
    
    @MainActor func windowViewer(root: TableRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return TableSheet(model: model, showTopImage: false, dismissAction: nil)
    }

    @MainActor func inlineViewer(root: TableRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return TableSheet(model: model, showTopImage: false, dismissAction: dismissAction)
    }
    
    @MainActor func selectionView(model: ItemSelectionModel) -> some View {
        LinkRootView(type: .selection)
            .environment(model)
    }
}

// MARK: - old

public extension ViewController {
    @MainActor
    func detailEditor(root: TableRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        TableDetailSheet(item: item)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(root: TableRootModel, select: Bool = false) -> some View {
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
    func generatorEditorWindow(root: TableRootModel) -> some View {
        GeneratorWindow(root: root)
            .environment(root)
    }

    @MainActor
    private static let linkTabId = UUID()

    @MainActor
    func tableSheetWindow(root: TableRootModel, selection: ItemSelection) -> some View {
        TableSheet(model: root.itemController.itemOrEmpty(for: selection.itemId), showTopImage: true, dismissAction: nil)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(root: TableRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = true, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: isGroupHidden, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }

    func rowView(root: TableRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        TableRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }
    
    @MainActor
    func generatorRow(root: TableRootModel, controllable: GeneratorControllable?, item: ItemRowTreeModel) -> some View {
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
    func gameTableView(root: TableRootModel) -> some View {
        TableGameSheet()
            .environment(root)
            .environment(\.showGame, true)
    }
}

// MARK: Links

public extension ViewController {
    @MainActor
    func selectForScan(root: TableRootModel, ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
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

public extension ViewController {
    @MainActor
    func viewGenerator(root: TableRootModel, with id: UUID, dismissAction: @escaping (UUID?) -> Void) -> some View {
        GeneratorRoot(generatorController: root.generatorController(rootItem: ItemRowModel(itemId: id, typeId: .table)), item: .constant(nil))
    }
}

// MARK: - Dice

extension ViewController {
    @MainActor @ViewBuilder
    func rowDiceView(root: TableRootModel, for id: UUID?, cacheItemListModel: CacheItemListModel) -> some View {
        if let id {
            root.diceRoot.viewController.viewRow(root: root.diceRoot, item: ItemRowTreeModel(itemId: id, typeId: .table), isSelected: false, cacheItemListModel: cacheItemListModel)
        } else {
            EmptyView()
        }
    }

    @MainActor @ViewBuilder
    func diceView(root: TableRootModel, for id: UUID?, from itemId: UUID) -> some View {
        if let id {
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: id, for: ResultCategory(id: itemId, module: root.itemController.itemDataModel.networkModule))
        } else {
            EmptyView()
        }
    }
}
