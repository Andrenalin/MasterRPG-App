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

    @MainActor public func thumbnailRowView(for model: any ItemDataAccessible) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: model.id, item: model as? MapModel).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination, sourceModel: sourceModel).equatable())
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
    
    @MainActor func mapEditWindow(root: MapRootModel, isTileEditor: Bool = false) -> some View {
        MapEditWindow(isTileEditor: isTileEditor)
    }
    
    @MainActor func gameView(root: MapRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor
    func gameMapView(
        root: MapRootModel,
        playerId: UUID,
        external: Bool = false,
        trailingViewportReservation: CGFloat = 0
    ) -> some View {
        RootCanvasMap(
            root: root,
            itemId: root.gameController.gameModel.currentItemId ?? UUID(),
            mode: .player,
            playerPinId: playerId,
            registersGameToolbarSession: !external,
            trailingViewportReservation: trailingViewportReservation
        )
            .environment(root)
    }

    @MainActor
    func gameMasterMapView(
        root: MapRootModel,
        id: UUID?,
        trailingViewportReservation: CGFloat = 0
    ) -> some View {
        let itemId = id ?? UUID()
        return RootCanvasMap(
            root: root,
            itemId: itemId,
            mode: .master,
            playerPinId: nil,
            trailingViewportReservation: trailingViewportReservation
        )
            .environment(root)
    }
    
    @MainActor @ViewBuilder
    func gameToolBarView(root: MapRootModel, isMaster: Bool) -> some View {
        if let model = root.rootModel.gameEditorModel {
            GameToolBar(editController: root.editController, model: model, isMaster: isMaster)
                .environment(root)
        }
    }

    /// Cross-module entry point: other modules (GameRPG's 3D table) reach the
    /// same `GameToolBar` this way, supplying their own `GameToolBarSession`
    /// conformance instead of the 2D map's `MapEditorSession`.
    @MainActor @ViewBuilder
    func gameToolBarView<Session: GameToolBarSession>(
        root: MapRootModel,
        isMaster: Bool,
        session: Session
    ) -> some View {
        GameToolBar(editController: root.editController, model: session, isMaster: isMaster)
            .environment(root)
    }
}
