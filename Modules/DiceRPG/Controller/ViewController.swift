// @copyright André Trettin

import CoreRPG
import Observation
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .none
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: itemId).equatable())
    }
}

// MARK: Viewer

public extension ViewController {
    func dropChooseView(model: ItemSelectionModel) -> some View {
        DiceDropChooseView(model: model)
            .environment(model)
    }

    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }
}

public extension ViewController {
    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(root: DiceRootModel, select: Bool = false) -> some View {
        var model: ItemRowModel? = nil
        if select == true, let id = root.gameController.gameModel.currentItemId {
            let item = root.gameController.gameItem(for: id)
            if item.displayState == 0 {
                model = ItemRowModel(itemId: id, typeId: .dice)
                let _ = root.listController(tabId: ViewController.gameTabId, focus: model)
            }
        }
        return RootNaviList(root: root, tabId: ViewController.gameTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false, disableSelection: true)
            .environment(root)
    }

    func diceRollView(root: DiceRootModel) -> some View {
        DiceFocusRoll()
            .environment(root)
    }

    func diceActionBarView(root: DiceRootModel) -> some View {
        DiceFocusActionBar()
            .environment(root)
    }

    func diceResultView(root: DiceRootModel) -> some View {
        DiceFocusResult()
            .environment(root)
    }

    func dicePlayerView(root: DiceRootModel) -> some View {
        DicePlayerRoot()
            .environment(root)
    }

    func overlayGameView(root: DiceRootModel, hideDice: Bool) -> some View {
        RootDiceOverlay(hideDice: hideDice)
            .environment(root)
    }
}

// MARK: - Links

public extension ViewController {
    @MainActor
    func selectForScan(root: DiceRootModel, ids: Binding<[UUID]?>, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(root: root, filter: .table) {
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

// MARK: - Selection

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(root: DiceRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: false, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
            .environment(SelectionSheetLinkModel())
    }
}

// MARK: - Dice

public extension ViewController {
    @MainActor
    func viewRow(root: DiceRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        DiceRow(item: item, isSelected: false, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    func viewCompactDice(root: DiceRootModel, itemId: UUID) -> some View {
        let item = root.itemController.itemOrEmpty(for: itemId)
        return Text(item.inlineText)
    }

    @MainActor
    func viewDice(root: DiceRootModel, with id: UUID?, for resultCategory: ResultCategory, onlyPrimaryAction: Bool = false) -> some View {
        DiceInline(itemId: id ?? UUID(), resultCategory: resultCategory, onlyPrimaryAction: onlyPrimaryAction)
            .environment(root)
    }
    
    @MainActor
    func viewDiceDropDownMenu(root: DiceRootModel, editController: any EditControllable, model: Binding<UUID?>) -> some View {
        DiceDropDownMenuArea(editController: editController, model: model)
            .environment(root)
    }
}

extension ViewController {
    @MainActor public func gameGiceHeight(root: DiceRootModel) -> CGFloat {
        guard let itemId = root.gameController.gameModel.currentItemId else { return 82.0 }
        let dice = root.gameController.gameItem(for: itemId)
        return height(for: dice)
    }

    @MainActor
    func height(for dice: DiceModel, minResult: Int = 0, maxResult: Int = 25) -> CGFloat {
        var values = dice.dice.reduce(0) { $1.result.count > $0 ? $1.result.count : $0 } - 1
        values = min(max(minResult, values), maxResult)
        return CGFloat(values) * 36.0 + 82.0
    }
    
    @MainActor
    func width(for dice: DiceModel, maxWidth: CGFloat) -> CGFloat {
        var values = dice.entries.count
        values = max(1, values)
#if os(visionOS)
        return min(CGFloat(values) * 112 + 20, maxWidth)
#else
        return min(CGFloat(values) * 56 + 20, maxWidth)
#endif

    }
}
