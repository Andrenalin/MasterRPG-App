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
    // The pickers bring the module roots they read with them. A presenter outside the app's
    // window hierarchy (the visionOS 3D table's volumetric window) injects almost none, and a
    // missing root is a fatal error in the picker. A character row shows its photo, so the
    // character picker needs the photo root too.
    @MainActor func characterSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.characterRoot.viewController.linkListView(type: .selection, itemSelectionModel: selectionModel)
            .environment(root.characterRoot)
            .environment(root.photoRoot)
    }
    
    @MainActor func photoSelection(root: MapRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.photoRoot.viewController.linkListView(type: .selection, itemSelectionModel: selectionModel)
            .environment(root.photoRoot)
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

    /// The one popover placement every cross-module popover shares, for a map surface other than
    /// the 2D canvas, GameRPG's camera-based 3D table: `source` is the anchor's frame inside a
    /// viewport of `viewportSize`; the returned view fills that viewport, like the 2D canvas'
    /// own overlay layer. `root` is the environment the content reads, when it reads any.
    @MainActor
    private func gamePopover<Content: View>(
        root: MapRootModel?,
        source: CGRect,
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets,
        onDismiss: @escaping @MainActor () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MapPopover(
            source: source,
            viewportRectangle: .unobscuredViewport(size: viewportSize, safeAreaInsets: safeAreaInsets),
            onDismiss: onDismiss,
            content: content
        )
        .environment(root)
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
    }

    /// Cross-module entry point: the game master's pin action popover. The caller performs the
    /// actions.
    @MainActor
    func gamePinActionPopover(
        pin: MapPinModel,
        source: CGRect,
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets,
        showsBattleAction: Bool,
        onDismiss: @escaping @MainActor () -> Void,
        perform: @escaping @MainActor (MapPinButtonType) -> Void
    ) -> some View {
        gamePopover(root: nil, source: source, viewportSize: viewportSize, safeAreaInsets: safeAreaInsets, onDismiss: onDismiss) {
            MapPinGameActionMenu(
                pin: pin,
                actions: Self.gamePinActions(showsBattleAction: showsBattleAction),
                axis: .vertical,
                perform: perform
            )
        }
    }

    /// Cross-module entry point: the pin photo popover. Placed like `gamePinActionPopover`.
    @MainActor
    func gamePinPhotoPopover(
        root: MapRootModel,
        pin: MapPinModel,
        source: CGRect,
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets,
        onShowFullScreen: (@MainActor () -> Void)?,
        onDismiss: @escaping @MainActor () -> Void
    ) -> some View {
        gamePopover(root: root, source: source, viewportSize: viewportSize, safeAreaInsets: safeAreaInsets, onDismiss: onDismiss) {
            MapPinPhotoPopoverContent(pin: pin, onShowFullScreen: onShowFullScreen, onClose: onDismiss)
        }
    }

    /// Cross-module entry point: the photo the game master shows on the map (see
    /// `MapPhotoPopoverModel`). `source` is the projected anchor
    /// (`MapPhotoPopoverSource.rectangle(atViewportPoint:)`). Placed like `gamePinPhotoPopover`.
    @MainActor
    func gameMapPhotoPopover(
        root: MapRootModel,
        photo: MapPhotoPopoverItem,
        source: CGRect,
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        let popover = root.photoPopover
        return gamePopover(root: root, source: source, viewportSize: viewportSize, safeAreaInsets: safeAreaInsets, onDismiss: { popover.close() }) {
            MapPhotoPopoverContent(
                item: photo,
                onShowFullScreen: { popover.showFullScreen() },
                onClose: { popover.close() }
            )
        }
    }

    /// Cross-module entry point: shows a pin's photo full screen during a game, from a map
    /// surface other than the 2D canvas. `isShared` when the game master shows a pin the players
    /// see. The caller closes the pin's popover first.
    @MainActor
    func showPinPhotoFullScreen(root: MapRootModel, pin: MapPinModel, mapId: UUID, isShared: Bool) {
        root.photoPopover.showFullScreen(pin: pin, mapId: mapId, isShared: isShared)
    }

#if os(visionOS)
    /// The one attachment every cross-module popover shares: the panel standing above its anchor
    /// in the table volume, with the arrow's tip at the center of the view's bottom edge.
    @MainActor
    private func gameAttachment<Content: View>(
        root: MapRootModel?,
        onDismiss: @escaping @MainActor () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MapPopoverAttachment(onDismiss: onDismiss, content: content)
            .environment(root)
    }

    /// The photo the game master shows on the map as an attachment, like `gamePinPhotoAttachment`.
    @MainActor
    func gameMapPhotoAttachment(root: MapRootModel, photo: MapPhotoPopoverItem) -> some View {
        let popover = root.photoPopover
        return gameAttachment(root: root, onDismiss: { popover.close() }) {
            MapPhotoPopoverContent(
                item: photo,
                onShowFullScreen: { popover.showFullScreen() },
                onClose: { popover.close() }
            )
        }
    }

    /// The pin photo popover as an attachment, standing above the pin like
    /// `gamePinActionAttachment`.
    @MainActor
    func gamePinPhotoAttachment(
        root: MapRootModel,
        pin: MapPinModel,
        onShowFullScreen: (@MainActor () -> Void)?,
        onDismiss: @escaping @MainActor () -> Void
    ) -> some View {
        gameAttachment(root: root, onDismiss: onDismiss) {
            MapPinPhotoPopoverContent(pin: pin, onShowFullScreen: onShowFullScreen, onClose: onDismiss)
        }
    }

    /// The pin action popover as an attachment: a row above the pin.
    @MainActor
    func gamePinActionAttachment(
        pin: MapPinModel,
        showsBattleAction: Bool,
        onDismiss: @escaping @MainActor () -> Void,
        perform: @escaping @MainActor (MapPinButtonType) -> Void
    ) -> some View {
        gameAttachment(root: nil, onDismiss: onDismiss) {
            MapPinGameActionMenu(
                pin: pin,
                actions: Self.gamePinActions(showsBattleAction: showsBattleAction),
                axis: .horizontal,
                perform: perform
            )
        }
    }

    /// The popover panel as a RealityKit attachment around `content`, for the dice results on
    /// the visionOS table. It is never dismissed; `isInteractive` decides whether `content`
    /// takes taps or lets them through to the table. Like `gamePinActionAttachment`, the
    /// arrow's tip is at the center of the view's bottom edge.
    @MainActor
    func tablePopoverLabel<Content: View>(
        isInteractive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MapPopoverAttachment(isInteractive: isInteractive, content: content)
    }
#endif

    private static func gamePinActions(showsBattleAction: Bool) -> [MapPinButtonType] {
        MapPinActionContext.gameMaster.actions.filter { showsBattleAction || $0 != .battle }
    }
}
