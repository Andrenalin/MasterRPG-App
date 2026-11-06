// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import MapRPG
import SwiftUI

// The game master's pin actions on the 3D table: the same popover as on the 2D map
// (`MapPopover`), pointing at the selected pin. The camera-based table draws it in the table
// view over the pin's projection; the visionOS volume shows it as an attachment above the pin.

#if os(visionOS)
/// Reports an attachment's own height to the model, which raises the attachment by half of it
/// so the arrow's tip, at the bottom of the view, ends at the target.
private struct ReportsAttachmentHeight: ViewModifier {
    let game: GameTableModel
    let kind: TablePopoverKind

    @Environment(\.physicalMetrics) private var physicalMetrics

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            game.attachmentHeightChanged(Float(physicalMetrics.convert(height, to: .meters)), for: kind)
        }
    }
}

/// The pin action popover as the table volume's "pin-menu" attachment.
@MainActor
struct GamePinActionMenu: View {
    let game: GameTableModel

    var body: some View {
        if let pin = game.selectedPin, game.isGameMaster {
            game.mapRoot.viewController.gamePinActionAttachment(
                pin: pin,
                showsBattleAction: game.canAddSelectedPinToBattleRound,
                onDismiss: { game.clearPinSelection() },
                perform: { game.performSelectedPinAction($0) }
            )
            .modifier(ReportsAttachmentHeight(game: game, kind: .pinMenu))
        }
    }
}

/// The pin photo popover as the table volume's "pin-photo" attachment.
@MainActor
struct GamePinPhotoPopover: View {
    let game: GameTableModel

    var body: some View {
        if let pin = game.photoPin {
            game.mapRoot.viewController.gamePinPhotoAttachment(
                root: game.mapRoot,
                pin: pin,
                onShowFullScreen: game.pinPhotoFullScreenAction,
                onDismiss: { game.dismissPinPhoto() }
            )
            .modifier(ReportsAttachmentHeight(game: game, kind: .pinPhoto))
        }
    }
}

/// The photo the game master shows on the map as the table volume's "map-photo" attachment.
@MainActor
struct GameMapPhotoPopover: View {
    let game: GameTableModel

    var body: some View {
        if let photo = game.mapPhoto, game.mapPhotoPosition != nil {
            game.mapRoot.viewController.gameMapPhotoAttachment(root: game.mapRoot, photo: photo)
                .modifier(ReportsAttachmentHeight(game: game, kind: .mapPhoto))
        }
    }
}
#else
/// A popover over the camera-based table. Fills the table view, whose coordinate space the
/// popover's source is in. Shown once its target is projected into the table view, and faded in
/// and out; following the target stays immediate. No fade with Reduce Motion. See
/// CODE_AUDIT_21 §8.4.
@MainActor
private struct TablePopoverHost<Content: View>: View {
    let game: GameTableModel
    let kind: TablePopoverKind
    /// What the popover belongs to when it is open: a pin's or the photo's id.
    let itemId: UUID?
    @ViewBuilder let content: (CGRect) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let source = game.popoverSources[kind]
        let presentedId = itemId == source?.id ? itemId : nil

        ZStack(alignment: .topLeading) {
            if presentedId != nil, let source {
                content(source.frame)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .default, value: presentedId)
    }
}

/// The game master's pin action popover over the camera-based table.
@MainActor
struct GamePinActionMenu: View {
    let game: GameTableModel
    let viewport: GameTableViewport

    var body: some View {
        TablePopoverHost(game: game, kind: .pinMenu, itemId: game.popoverPinId(for: .pinMenu)) { frame in
            if let pin = game.selectedPin {
                game.mapRoot.viewController.gamePinActionPopover(
                    pin: pin,
                    source: frame,
                    viewportSize: viewport.size,
                    safeAreaInsets: viewport.safeAreaInsets,
                    showsBattleAction: game.canAddSelectedPinToBattleRound,
                    onDismiss: { game.clearPinSelection() },
                    perform: { game.performSelectedPinAction($0) }
                )
            }
        }
    }
}

/// The pin photo popover over the camera-based table, placed like `GamePinActionMenu`.
@MainActor
struct GamePinPhotoPopover: View {
    let game: GameTableModel
    let viewport: GameTableViewport

    var body: some View {
        TablePopoverHost(game: game, kind: .pinPhoto, itemId: game.popoverPinId(for: .pinPhoto)) { frame in
            if let pin = game.photoPin {
                game.mapRoot.viewController.gamePinPhotoPopover(
                    root: game.mapRoot,
                    pin: pin,
                    source: frame,
                    viewportSize: viewport.size,
                    safeAreaInsets: viewport.safeAreaInsets,
                    onShowFullScreen: game.pinPhotoFullScreenAction,
                    onDismiss: { game.dismissPinPhoto() }
                )
            }
        }
    }
}

/// The photo the game master shows on the map, over the camera-based table, placed like
/// `GamePinPhotoPopover` at the projected anchor.
@MainActor
struct GameMapPhotoPopover: View {
    let game: GameTableModel
    let viewport: GameTableViewport

    var body: some View {
        let photo = game.mapPhoto
        TablePopoverHost(game: game, kind: .mapPhoto, itemId: photo?.itemId) { frame in
            if let photo {
                game.mapRoot.viewController.gameMapPhotoPopover(
                    root: game.mapRoot,
                    photo: photo,
                    source: frame,
                    viewportSize: viewport.size,
                    safeAreaInsets: viewport.safeAreaInsets
                )
            }
        }
    }
}

/// The table view's size and the part of it system bars cover.
struct GameTableViewport: Equatable {
    var size = CGSize.zero
    var safeAreaInsets = EdgeInsets()
}
#endif

#endif
