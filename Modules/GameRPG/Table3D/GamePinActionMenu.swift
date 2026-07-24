// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import MapRPG
import PhotoRPG
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
            if game.canAddSelectedPinToBattleRound {
                GamePinMenuButton(
                    title: LocalizedStringResource("Add Pin to Battle Round", bundle: .module),
                    systemImage: "person.badge.plus",
                    action: game.addSelectedPinToBattleRound
                )
            }
        }
        .padding(12)
        .modifier(GamePinMenuBackground())
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

private struct GamePinMenuBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(visionOS)
        content.glassBackgroundEffect(in: .capsule)
#else
        content.background(.regularMaterial, in: .capsule)
#endif
    }
}

#Preview("Pin actions") {
    let game = GameTableModel(mapRoot: .preview, photoRoot: .preview)
    let pin = MapPinModel(
        id: UUID(),
        name: "Goblin Guard",
        color: .red,
        location: CGPoint(x: 160, y: 120)
    )

    GamePinActionMenuContent(game: game, pin: pin)
        .padding()
}

#endif
