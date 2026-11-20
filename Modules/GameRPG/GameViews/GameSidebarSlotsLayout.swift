// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Arranges the game master's sidebar panels: stacked in one column (`.single`), the Game View
/// above the second view (`.horizontal`), or the two side by side (`.vertical`).
///
/// A hidden panel stays mounted and slides out (see `gameSidePanel`), so the split slots are
/// fixed-size clear frames the panels fill, not stack children that would claim space while hidden.
struct GameSidebarSlotsLayout<Primary: View, Secondary: View>: View {
    let layout: GameSidebarLayout
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        switch layout {
        case .single:
            ZStack(alignment: .trailing) {
                primary()
                secondary()
            }
        case .horizontal:
            VStack(spacing: GameScreenModel.mapOverlaySpacing) {
                Color.clear.overlay(alignment: .trailing) {
                    primary().environment(\.gameSidePanelSlot, .top)
                }
                Color.clear.overlay(alignment: .trailing) {
                    ZStack(alignment: .trailing) {
                        secondary()
                    }
                    .environment(\.gameSidePanelSlot, .bottom)
                }
            }
        case .vertical:
            HStack(spacing: GameScreenModel.mapOverlaySpacing) {
                Color.clear
                    .frame(width: gameScreenModel.sideBarWidth)
                    .overlay(alignment: .trailing) {
                        primary().environment(\.gameSidePanelSlot, .leading)
                    }
                Color.clear
                    .frame(width: gameScreenModel.sideBarWidth)
                    .overlay(alignment: .trailing) {
                        ZStack(alignment: .trailing) {
                            secondary()
                        }
                        .environment(\.gameSidePanelSlot, .trailing)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

#Preview("Horizontal", traits: .mockData) {
    GameSidebarSlotsLayoutPreview(layout: .horizontal)
}

#Preview("Vertical", traits: .mockData) {
    GameSidebarSlotsLayoutPreview(layout: .vertical)
}

private struct GameSidebarSlotsLayoutPreview: View {
    let layout: GameSidebarLayout

    @State private var root = GameRoot.previewFixture()
    @State private var screenModel = GameScreenModel()

    var body: some View {
        GameSidebarSlotsLayout(layout: layout) {
            TabGameView(root: root, adventureId: GamePreviewData.adventureID)
        } secondary: {
            TabSecondGameView(root: root)
            BattleRoundSideOverlay(root: root)
        }
        .environment(screenModel)
        .environment(ScenesManager())
        .environment(AppFocusModel())
        .background(Color.brown)
        .onAppear {
            screenModel.sidebarLayout = layout
            screenModel.showMainTab = .game
        }
    }
}
