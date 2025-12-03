// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import TableRPG
import SwiftUI

public struct ViewController {
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
    func diceSelection(root: CharacterRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.selectionView(root: root.diceRoot, model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkWindow(isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(ItemSelectionModel())
    }
    
    @MainActor func windowViewer(root: CharacterRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return CharacterSheet(model: model, showTopImage: false, dismissAction: nil)
    }

    @MainActor func inlineViewer(root: CharacterRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return CharacterSheet(model: model, showTopImage: false, dismissAction: dismissAction)
    }
    
    @MainActor func selectionView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
}

// MARK: - OLd Views

public extension ViewController {
    @MainActor
    func detailEditor(for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        CharacterDetailSheet(item: item)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(root: CharacterRootModel, select: UUID? = nil) -> some View {
        if let id = select {
            let item = root.itemController.itemOrEmpty(for: id)
            if item.displayState == 0 {
                let model = ItemRowModel(itemId: id, typeId: root.itemController.itemDataModel.networkModule)
                let _ = root.listController(tabId: ViewController.gameTabId, focus: model)
            }
        }
        return RootNaviList(root: root, tabId: ViewController.gameTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false, disableSelection: true)
    }
    
    @MainActor
    func generatorEditorWindow(root: CharacterRootModel) -> some View {
        GeneratorWindow(root: root)
            .environment(root)
    }

    @MainActor
    private static let linkTabId = UUID()

    @MainActor
    func characterWindow(root: CharacterRootModel, selection: ItemSelection) -> some View {
        CharacterSheet(model: root.itemController.itemOrEmpty(for: selection.itemId), showTopImage: true, dismissAction: nil)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    func rowView(root: CharacterRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        ValueRow(item: item, isSelected: isSelected, hasQuickEditor: true, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(root: CharacterRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = true, focus: UUID? = nil, searchText: String? = nil, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: isGroupHidden, focus: focus, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        if let searchText {
            listController.setSearchFilter(text: searchText)
        }
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }

    @MainActor
    func viewSelectCharacters(root: CharacterRootModel, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(root: root, filter: .character, onlyItems: true, selection: selection, toggleSelection: toggleSelection, dismissAction: dismissAction)
    }

    @MainActor 
    func viewSelectMasters(root: CharacterRootModel, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(root: root, filter: .gameMaster, onlyItems: true, selection: selection, toggleSelection: toggleSelection, dismissAction: dismissAction)
    }

    @MainActor
    func viewMinimum(root: CharacterRootModel, with id: UUID?) -> some View {
        MinimumRow(itemId: id ?? UUID())
            .environment(root)
    }
}

public extension ViewController {
    @MainActor 
    func selectForScan(root: CharacterRootModel, ids: Binding<[UUID]?>, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(root: root) {
            if let links = ids.wrappedValue {
                return links.map { ItemRowModel(itemId: $0, typeId: root.itemController.itemDataModel.networkModule) }
            } else {
                return []
            }
        } toggleSelection: { selection, _ in
            if let index = ids.wrappedValue?.firstIndex(of: selection.itemId) {
                ids.wrappedValue?.remove(at: index)
            } else {
                if ids.wrappedValue == nil {
                    ids.wrappedValue = []
                }
                ids.wrappedValue?.append(selection.itemId)
            }
        } dismissAction: {
            dismissAction()
        }
    }
}
