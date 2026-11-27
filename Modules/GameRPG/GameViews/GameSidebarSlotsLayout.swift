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
    var placement: GameSidebarPlacement = .trailing
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        if placement == .bottom {
            // Read here, not inside the layout closure below: that closure runs at layout time
            // and does not observe the model, so a change would only show on the next rebuild.
            let heightFraction = gameScreenModel.bottomSidebarHeightFraction
            // The container excludes the safe areas the panel runs under: the share is of the screen.
            let safeAreaHeight = gameScreenModel.chromeTopSafeAreaInset + gameScreenModel.chromeBottomSafeAreaInset
            // One view at a time in a full-width panel at the bottom. The height is a share of the
            // container's, set outside the stack so a hidden panel (kept mounted, slid out) claims nothing.
            ZStack(alignment: .bottom) {
                primary()
                secondary()
            }
            .environment(\.gameSidePanelSlot, .bottomPanel)
            .containerRelativeFrame(.vertical, alignment: .bottom) { length, _ in
                (length + safeAreaHeight) * heightFraction
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(accessibilityReduceMotion ? nil : .default, value: heightFraction)
        } else {
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
}

#Preview("Horizontal", traits: .mockData) {
    GameSidebarSlotsLayoutPreview(layout: .horizontal)
}

#Preview("Vertical", traits: .mockData) {
    GameSidebarSlotsLayoutPreview(layout: .vertical)
}

#Preview("Bottom", traits: .mockData) {
    GameSidebarSlotsLayoutPreview(layout: .single, placement: .bottom)
}

private struct GameSidebarSlotsLayoutPreview: View {
    let layout: GameSidebarLayout
    var placement: GameSidebarPlacement = .trailing

    @State private var root = GameRoot.previewFixture()
    @State private var screenModel = GameScreenModel()

    var body: some View {
        GameSidebarSlotsLayout(layout: layout, placement: placement) {
            TabGameView(root: root, adventureId: GamePreviewData.adventureId)
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
            screenModel.sidebarPlacement = placement
            screenModel.showMainTab = .game
        }
    }
}

/// Applies the effective sidebar layout and placement to the screen model: the saved choices,
/// where they are offered (layouts on iPad for the game master, the bottom placement on iPhone).
struct GameSidebarLayoutSyncModifier: ViewModifier {
    let isMaster: Bool

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel

    private struct Effective: Equatable {
        var layout: GameSidebarLayout
        var placement: GameSidebarPlacement
        var isCompact: Bool
    }

    private var effective: Effective {
        if appWindowSizeModel.mode == .regular {
            let layout = isMaster
                ? GameSidebarLayout(rawValue: appSettingsModel.masterSidebarLayout) ?? .single
                : .single
            return Effective(layout: layout, placement: .trailing, isCompact: false)
        }
        let saved = isMaster ? appSettingsModel.masterSidebarPlacement : appSettingsModel.playerSidebarPlacement
        return Effective(
            layout: .single,
            placement: GameSidebarPlacement(rawValue: saved) ?? .trailing,
            isCompact: true
        )
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: effective, initial: true) { _, effective in
                gameScreenModel.sidebarLayout = effective.layout
                gameScreenModel.sidebarPlacement = effective.placement
                gameScreenModel.isCompactWidth = effective.isCompact
            }
    }
}

extension View {
    func gameSidebarLayoutSync(isMaster: Bool) -> some View {
        modifier(GameSidebarLayoutSyncModifier(isMaster: isMaster))
    }
}
