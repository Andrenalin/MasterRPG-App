// @copyright André Trettin

import CharacterRPG
import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PhotoRPG
import SwiftUI

public struct ViewController {
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }
}

// MARK: - Batch Extraction

#if !os(tvOS)
extension ViewController {
    public var supportsBatchExtraction: Bool { true }

    @MainActor public func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? {
        guard itemController is ItemController else { return nil }
        return AnyView(
            BatchTextSummaryExtractionView(
                module: .map,
                ids: ids,
                itemController: itemController,
                editController: editController
            )
        )
    }
}
#endif

// MARK: External Views

extension ViewController {
    @MainActor func characterSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.characterRoot.viewController.linkListView(type: .selection, itemSelectionModel: selectionModel)
    }
    
    @MainActor func diceSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.dropChooseView(model: selectionModel)
    }
    
    @MainActor func photoSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.photoRoot.viewController.linkListView(type: .selection, itemSelectionModel: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }

    @MainActor func windowViewer(root: MapRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, configuration: ViewerConfiguration(addToolbar: true), dismissAction: nil)
    }

    @MainActor func viewer(root: MapRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return ViewerRootView(model: model, configuration: configuration, dismissAction: dismissAction)
    }
    
    @MainActor func mapEditWindow(root: MapRootModel) -> some View {
        MapEditWindow()
    }
    
    @MainActor func gameView(root: MapRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor
    func gameMapView(root: MapRootModel, playerId: UUID, external: Bool = false) -> some View {
        RootCanvasMap(root: root, itemId: root.gameController.gameModel.currentItemId ?? UUID(), mode: .player, playerPinId: playerId)
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
        return RootCanvasMap(root: root, itemId: itemId, mode: .master, playerPinId: nil)
            .environment(root)
    }
    
    @MainActor @ViewBuilder
    func gameToolBarView(root: MapRootModel, isMaster: Bool) -> some View {
        if let model = root.rootModel.gameEditorModel {
            GameToolBar(editController: root.editController, model: model, isMaster: isMaster)
                .environment(root)
        }
    }
}
