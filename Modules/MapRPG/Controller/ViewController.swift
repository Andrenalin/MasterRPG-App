// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG
import CharacterRPG

public struct ViewController {
    public let goupViewType: GroupViewType = .none
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source).equatable())
    }
}

// MARK: External Views

extension ViewController {
    @MainActor func diceSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.dropChooseView(model: selectionModel)
    }
    
    @MainActor func characterSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.characterRoot.viewController.linkListView(type: .selection, itemSelectionModel: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func windowViewer(root: MapRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, dismissAction: nil)
    }

    @MainActor func inlineViewer(root: MapRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, dismissAction: dismissAction)
    }
    
    @MainActor func mapEditWindow(root: MapRootModel) -> some View {
        MapEditWindow(editController: root.editController)
    }
    
    @MainActor func gameView(root: MapRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
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

// MARK: Links

public extension ViewController {
    @MainActor 
    func selectForScan(root: MapRootModel, ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
        Text("ToDO")
    }
}
