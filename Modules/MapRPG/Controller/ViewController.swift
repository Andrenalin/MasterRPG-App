// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

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
    func diceSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.dropChooseView(model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkWindow(isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(ItemSelectionModel())
    }
    
    @MainActor func windowViewer(root: MapRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return MapSheet(model: model, showTopImage: false, dismissAction: nil)
    }

    @MainActor func inlineViewer(root: MapRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return MapSheet(model: model, showTopImage: false, dismissAction: dismissAction)
    }
    
    @MainActor func selectionView(model: ItemSelectionModel) -> some View {
        LinkRootView(type: .selection)
            .environment(model)
    }
}

// MARK: - OLd Views

public extension ViewController {
    @MainActor
    private static let linkTabId = UUID()

    @MainActor
    func mapEditWindow(root: MapRootModel) -> some View {
        MapEditWindow(editController: root.editController)
            .environment(root)
    }

    @MainActor
    func mapBookWindow(root: MapRootModel, selection: ItemSelection) -> some View {
        MapReader(map: root.itemController.itemOrEmpty(for: selection.itemId))
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    @MainActor
    func detailEditor(root: MapRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        MapDetailSheet(item: item)
            .environment(root)
    }

    func rowView(root: MapRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        MapRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(root: MapRootModel, select: Bool = false) -> some View {
        var model: ItemRowModel? = nil
        if select == true, let id = root.gameController.gameModel.currentItemId {
            let item = root.gameController.gameItem(for: id)
            if item.displayState == 0 {
                model = ItemRowModel(itemId: id, typeId: .map)
                let _ = root.listController(tabId: ViewController.gameTabId, focus: model)
            }
        }
        return RootNaviList(root: root, tabId: ViewController.gameTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false, disableSelection: true)
            .environment(root)
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor
    func gameMapView(root: MapRootModel, playerId: UUID, external: Bool = false) -> some View {
        RootCanvasMap(root: root, itemId: root.gameController.gameModel.currentItemId ?? UUID(), mode: .player, toolBarModel: external ? GameToolBarModel() : root.rootModel.toolBarModel, playerPinId: playerId)
            .environment(root)
    }

    @MainActor
    func gameMasterMapView(root: MapRootModel, id: UUID?) -> some View {
        let itemId = id ?? UUID()
        let gameController = root.gameController
        gameController.mapGameModel.playerPins.forEach { pin in
            if let pinIndex = gameController.gameItem(for: itemId).mapPins.firstIndex(where: { $0.id == pin.id }) {
                if pin.timeInterval > gameController.gameItem(for: itemId).mapPins[pinIndex].timeInterval {
                    gameController.gameItem(for: itemId)[MapPinId.id, pin.id] = pin
                }
            } else {
                var resetPin = pin
                resetPin.location = .zero
                resetPin.timeInterval = Date.now.timeIntervalSince1970
                gameController.gameItem(for: itemId).mapPins.append(resetPin)
            }
        }
        return RootCanvasMap(root: root, itemId: itemId, mode: .master, toolBarModel: root.rootModel.toolBarModel, playerPinId: nil)
            .environment(root)
    }
    
    @MainActor
    func gameToolBarView(root: MapRootModel, isMaster: Bool) -> some View {
        GameToolBar(editController: root.editController, model: root.rootModel.toolBarModel, isMaster: isMaster)
            .environment(root)
    }
}

// MARK: Selection

public extension ViewController {
    @MainActor
    private static let selectionTabId = UUID()

    @MainActor
    func viewSelect(root: MapRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
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

// MARK: Links

public extension ViewController {
    @MainActor 
    func selectForScan(root: MapRootModel, ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
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
