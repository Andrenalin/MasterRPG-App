// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
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
        ViewThatFits(in: .horizontal) {
            HStack { GamePinMenuButtons(game: game, pin: pin) }
            ScrollView(.horizontal) { HStack { GamePinMenuButtons(game: game, pin: pin) } }
                .scrollIndicators(.hidden)
        }
        .padding()
    }
}

/// The menu's buttons, as their own `View` so both `ViewThatFits` layouts share one definition.
@MainActor
private struct GamePinMenuButtons: View {
    let game: GameTableModel
    let pin: MapPinModel

    var body: some View {
        Group {
            GamePinMenuButton(
                title: pin.isDead
                    ? LocalizedStringResource("Revive Pin", bundle: .module)
                    : LocalizedStringResource("Mark Pin Dead", bundle: .module),
                systemImage: pin.isDead ? "heart.fill" : "xmark",
                isSelected: pin.isDead,
                action: game.toggleSelectedPinDead
            )
            GamePinMenuButton(
                title: pin.isShown
                    ? LocalizedStringResource("Hide Pin", bundle: .module)
                    : LocalizedStringResource("Show Pin", bundle: .module),
                systemImage: pin.isShown ? "eye.slash" : "eye",
                isSelected: pin.isShown,
                action: game.toggleSelectedPinVisibility
            )
            GamePinMenuButton(
                title: LocalizedStringResource("Resize Pin", bundle: .module),
                systemImage: "square.resize",
                isSelected: false,
                action: game.resizeSelectedPin
            )
            GamePinMenuButton(
                title: pin.isZoom
                    ? LocalizedStringResource("Reset Pin Zoom", bundle: .module)
                    : LocalizedStringResource("Zoom Pin", bundle: .module),
                systemImage: pin.isZoom ? "minus.magnifyingglass" : "plus.magnifyingglass",
                isSelected: pin.isZoom,
                action: game.toggleSelectedPinZoom
            )
            GamePinMenuButton(
                title: pin.isHighlighted
                    ? LocalizedStringResource("Remove Pin Highlight", bundle: .module)
                    : LocalizedStringResource("Highlight Pin", bundle: .module),
                systemImage: pin.isHighlighted ? "circle.fill" : "circle",
                isSelected: pin.isHighlighted,
                action: game.toggleSelectedPinHighlight
            )
            if game.canAddSelectedPinToBattleRound {
                GamePinMenuButton(
                    title: LocalizedStringResource("Add Pin to Battle Round", bundle: .module),
                    systemImage: "person.badge.plus",
                    isSelected: false,
                    action: game.addSelectedPinToBattleRound
                )
            }
        }
    }
}

private struct GamePinMenuButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    let isSelected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .selectedRoundButton(
            title: String(localized: title),
            module: .table,
            isSelected: isSelected
        )
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
