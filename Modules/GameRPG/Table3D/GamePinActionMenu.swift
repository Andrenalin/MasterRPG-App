// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import MapRPG
import SwiftUI

// The game master's pin actions on the 3D table: the same popover as on the 2D map
// (`MapPopover`), pointing at the selected pin. The camera-based table draws it in the table
// view over the pin's projection; the visionOS volume shows it as an attachment above the pin.

#if os(visionOS)
/// The pin action popover as the table volume's "pin-menu" attachment.
@MainActor
struct GamePinActionMenu: View {
    let game: GameTableModel

    @Environment(\.physicalMetrics) private var physicalMetrics

    var body: some View {
        if let pin = game.selectedPin, game.isGameMaster {
            game.mapRoot.viewController.gamePinActionAttachment(
                pin: pin,
                showsBattleAction: game.canAddSelectedPinToBattleRound,
                onDismiss: { game.clearPinSelection() },
                perform: { game.performSelectedPinAction($0) }
            )
            // The model raises the attachment by half its height, so the arrow's tip, at the
            // bottom of this view, ends at the pin.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                game.pinMenuAttachmentHeightChanged(
                    Float(physicalMetrics.convert(height, to: .meters))
                )
            }
        }
    }
}
#else
/// The pin action popover over the camera-based table. Fills the table view, whose coordinate
/// space `GameTableModel.pinMenuSource` is in.
@MainActor
struct GamePinActionMenu: View {
    let game: GameTableModel
    let viewport: GameTableViewport

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The pin the popover is open on: selected, and already projected into the table view.
    private var presentedPin: MapPinModel? {
        guard game.isGameMaster,
              let pin = game.selectedPin,
              game.pinMenuSource?.pinId == pin.id else { return nil }
        return pin
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let pin = presentedPin, let source = game.pinMenuSource {
                game.mapRoot.viewController.gamePinActionPopover(
                    pin: pin,
                    source: source.frame,
                    viewportSize: viewport.size,
                    safeAreaInsets: viewport.safeAreaInsets,
                    showsBattleAction: game.canAddSelectedPinToBattleRound,
                    onDismiss: { game.clearPinSelection() },
                    perform: { game.performSelectedPinAction($0) }
                )
                .transition(.opacity)
            }
        }
        // Fades the popover in and out; following the pin stays immediate. No fade with
        // Reduce Motion. See CODE_AUDIT_21 §8.4.
        .animation(reduceMotion ? nil : .default, value: presentedPin?.id)
    }
}

/// The table view's size and the part of it system bars cover.
struct GameTableViewport: Equatable {
    var size = CGSize.zero
    var safeAreaInsets = EdgeInsets()
}
#endif

#endif
