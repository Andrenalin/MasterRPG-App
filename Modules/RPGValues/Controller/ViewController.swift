// @copyright André Trettin

import AndrenalinKit
import PhotoRPG
import TableRPG
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .item
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo

    weak var root: CharacterRootModel!
}

extension ViewController: ViewControllable {
}

public extension ViewController {
    @MainActor
    func detailEditor(for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        CharacterDetailSheet(item: item)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(select: UUID? = nil) -> some View {
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
            .focusedSceneValue(\.selectedModule, .constant(root.itemController.itemDataModel.networkModule))
            .environment(root)
            .environment(SelectionSheetLinkModel())
    }

    @MainActor
    func characterWindow(selection: ItemSelection) -> some View {
        CharacterSheet(model: root.itemController.itemOrEmpty(for: selection.itemId), showTopImage: true, dismissAction: nil)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    func rowView(item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        ValueRow(item: item, isSelected: isSelected, hasQuickEditor: true, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, isGroupHidden: Bool = true, focus: UUID? = nil, searchText: String? = nil, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
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
    func viewSelectCharacters(selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(filter: .character, onlyItems: true, selection: selection, toggleSelection: toggleSelection, dismissAction: dismissAction)
    }

    @MainActor 
    func viewSelectMasters(selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(filter: .gameMaster, onlyItems: true, selection: selection, toggleSelection: toggleSelection, dismissAction: dismissAction)
    }

    @MainActor
    func viewMinimum(with id: UUID?) -> some View {
        MinimumRow(itemId: id ?? UUID())
            .environment(root)
    }
}

public extension ViewController {
    @MainActor 
    func selectForScan(ids: Binding<[UUID]?>, dismissAction: @escaping () -> Void) -> some View {
        viewSelect {
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
