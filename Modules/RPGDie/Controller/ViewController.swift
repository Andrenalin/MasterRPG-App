// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

public struct ViewController {
    weak var root: DiceRoot!
}

public extension ViewController {
    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(select: Bool = false) -> some View {
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

    func diceRollView() -> some View {
        DiceFocusRoll()
            .environment(root)
    }

    func diceActionBarView() -> some View {
        DiceFocusActionBar()
            .environment(root)
    }

    func diceResultView() -> some View {
        DiceFocusResult()
            .environment(root)
    }

    func dicePlayerView() -> some View {
        DicePlayerRoot()
            .environment(root)
    }

    func overlayGameView(hideDice: Bool) -> some View {
        RootDiceOverlay(hideDice: hideDice)
            .environment(root)
    }
}

// MARK: - Links

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
    func selectForScan(ids: Binding<[UUID]?>, dismissAction: @escaping () -> Void) -> some View {
        viewSelect(filter: .table) {
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
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
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
    func viewRow(item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        DiceRow(item: item, isSelected: false, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    func viewCompactDice(itemId: UUID) -> some View {
        let item = root.itemController.itemOrEmpty(for: itemId)
        return Text(item.inlineText)
    }

    @MainActor
    func viewDice(with id: UUID?, for resultCategory: ResultCategory, onlyPrimaryAction: Bool = false) -> some View {
        DiceInline(itemId: id ?? UUID(), resultCategory: resultCategory, onlyPrimaryAction: onlyPrimaryAction)
            .environment(root)
    }
    
    @MainActor
    func viewDiceDropDownMenu(editController: any EditControllable, model: Binding<UUID?>) -> some View {
        DiceDropDownMenuArea(editController: editController, model: model)
            .environment(root)
    }
}

extension ViewController {
    @MainActor public func gameGiceHeight() -> CGFloat {
        guard let itemId = root.gameController.gameModel.currentItemId else { return 82.0 }
        let dice = root.gameController.gameItem(for: itemId)
        return height(for: dice)
    }

    @MainActor
    func height(for dice: DiceModel, minResult: Int = 0, maxResult: Int = 25) -> CGFloat {
        var values = dice.entries.reduce(0) { $1.result.count > $0 ? $1.result.count : $0 } - 1
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
