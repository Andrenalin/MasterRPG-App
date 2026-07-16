// @copyright André Trettin

#if os(visionOS)
import MapRPG
import SwiftUI

@MainActor
struct GamePinActionMenu: View {
    let game: GameTableModel

    var body: some View {
        if let pin = game.selectedPin, game.isGameMaster {
            GamePinActionMenuContent(game: game, pin: pin)
        }
    }
}

@MainActor
private struct GamePinActionMenuContent: View {
    let game: GameTableModel
    let pin: MapPinModel

    var body: some View {
        HStack(spacing: 12) {
            GamePinMenuButton(
                title: pin.isDead
                    ? LocalizedStringResource("Revive Pin", bundle: .module)
                    : LocalizedStringResource("Mark Pin Dead", bundle: .module),
                systemImage: pin.isDead ? "heart.fill" : "xmark",
                action: game.toggleSelectedPinDead
            )
            GamePinMenuButton(
                title: pin.isShown
                    ? LocalizedStringResource("Hide Pin", bundle: .module)
                    : LocalizedStringResource("Show Pin", bundle: .module),
                systemImage: pin.isShown ? "eye.slash" : "eye",
                action: game.toggleSelectedPinVisibility
            )
            GamePinMenuButton(
                title: LocalizedStringResource("Resize Pin", bundle: .module),
                systemImage: "square.resize",
                action: game.resizeSelectedPin
            )
            GamePinMenuButton(
                title: pin.isZoom
                    ? LocalizedStringResource("Reset Pin Zoom", bundle: .module)
                    : LocalizedStringResource("Zoom Pin", bundle: .module),
                systemImage: pin.isZoom ? "minus.magnifyingglass" : "plus.magnifyingglass",
                action: game.toggleSelectedPinZoom
            )
        }
        .padding(12)
        .glassBackgroundEffect(in: .capsule)
    }
}

private struct GamePinMenuButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .help(Text(title))
    }
}

#endif
