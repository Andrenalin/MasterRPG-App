// @copyright André Trettin

import CoreRPG
import AudioRPG
import Foundation
import SwiftUI

struct OverlayGameMenu: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
#if os(visionOS)
        OverlayGameMenuVisionProMenuView(root: root, isMaster: isMaster, playerController: playerController, marginWidth: marginWidth)
#elseif os(macOS)
        OverlayGameMenuMacMenuView(
            root: root,
            isMaster: isMaster,
            playerController: playerController,
            marginWidth: marginWidth,
            onDisplayModeChange: { oldValue, newValue in
                handleMainTabDisplayModeChange(oldValue: oldValue, newValue: newValue, isMaster: isMaster)
            },
            onToggle: { newValue in
                handleMainTabToggle(isShown: newValue, isMaster: isMaster)
            }
        )
#elseif os(tvOS)
        OverlayGameMenuTvMenuView(
            root: root,
            isMaster: isMaster,
            playerController: playerController,
            marginWidth: marginWidth,
            onToggle: { newValue in
                handleMainTabToggle(isShown: newValue, isMaster: isMaster)
            }
        )
#else
        IOSGameOverlayMenu(
            root: root,
            playerController: playerController,
            isMaster: isMaster
        )
#endif
    }
}

private extension OverlayGameMenu {
    var marginWidth: CGFloat {
        appWindowSizeModel.mode == .compact ? 4 : 8
    }

    /// Menu-mode logic lives in `GameScreenModel` (testable); these only supply the environment.
    /// See CODE_AUDIT_17 §8.4.
    func handleMainTabToggle(isShown: Bool, isMaster: Bool) {
        gameScreenModel.applyMainTabToggle(
            isShown: isShown,
            isMaster: isMaster,
            settings: appSettingsModel,
            animated: !accessibilityReduceMotion
        )
    }

    func handleMainTabDisplayModeChange(oldValue: GameMainTabDisplayMode, newValue: GameMainTabDisplayMode, isMaster: Bool) {
        gameScreenModel.applyMainTabDisplayMode(
            newValue,
            isMaster: isMaster,
            settings: appSettingsModel,
            scenes: scenesManager,
            selectedItemId: isMaster ? root.gameModel.selectedAdventure : root.gameModel.selectedCharacter
        )
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `OverlayGameMenu` itself that all re-evaluated whenever any part
// of `OverlayGameMenu`'s body did.

#if os(visionOS)
private struct OverlayGameMenuVisionProMenuView: View {
    let root: GameRoot
    let isMaster: Bool
    let playerController: PlayerController?
    let marginWidth: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: marginWidth) {
            OverlayGameMenuTitleView(root: root, isMaster: isMaster)

            HStack(alignment: .bottom, spacing: marginWidth + 4) {
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: .top)
                    .padding(.horizontal, marginWidth)
                    .padding(.leading, marginWidth / 2)
                    .zIndex(2)

                // The players (game master) or companions (player) follow the volume.
                if root.offersTablePlayers(isMaster: isMaster) {
                    // The same button look and size as the volume and join code buttons next
                    // to it, so their bottoms line up.
                    TablePlayersButton(root: root)
                        .imageScale(.small)
                        .padding(.leading, marginWidth)
                }

                OverlayGameMenuWifiView(root: root, isMaster: isMaster, playerController: playerController, marginWidth: marginWidth)
            }
        }
    }
}
#endif

#if os(macOS)
private struct OverlayGameMenuMacMenuView: View {
    let root: GameRoot
    let isMaster: Bool
    let playerController: PlayerController?
    let marginWidth: CGFloat
    let onDisplayModeChange: (_ oldValue: GameMainTabDisplayMode, _ newValue: GameMainTabDisplayMode) -> Void
    let onToggle: (_ isShown: Bool) -> Void

    var body: some View {
        HStack {
            OverlayGameMenuTitleView(root: root, isMaster: isMaster)

            HStack {
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: .bottomTrailing)

                OverlayGameMenuToolIconView(root: root, isMaster: isMaster, marginWidth: marginWidth, onDisplayModeChange: onDisplayModeChange, onToggle: onToggle)
                OverlayGameMenuEnlargerView()

                OverlayGameMenuWifiView(root: root, isMaster: isMaster, playerController: playerController, marginWidth: marginWidth)
            }
            .foregroundStyle(.secondary)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))

            OverlayGameMenuCloseFieldView(marginWidth: marginWidth)
        }
    }
}
#endif

private struct OverlayGameMenuTvMenuView: View {
    let root: GameRoot
    let isMaster: Bool
    let playerController: PlayerController?
    let marginWidth: CGFloat
    let onToggle: (_ isShown: Bool) -> Void

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        @Bindable var gameScreenModel = gameScreenModel

        HStack {
            if isMaster || root.gameModel.gameType != .observer {
                GameDiceToggleButton()
            }
            Spacer()
            // An observer has no adventure or character side view to show.
            if isMaster || root.gameModel.gameType != .observer {
                GameMainTabToggleButtonView(isMaster: isMaster, isShown: $gameScreenModel.showMainTabIOS)
                    .onChange(of: gameScreenModel.showMainTabIOS) { _, newValue in
                        onToggle(newValue)
                    }
            }
            OverlayGameMenuWifiView(root: root, isMaster: isMaster, playerController: playerController, marginWidth: marginWidth)
            OverlayGameMenuCloseFieldView(marginWidth: marginWidth)
        }
        .focusSectionAll()
    }
}

private struct OverlayGameMenuTitleView: View {
    let root: GameRoot
    let isMaster: Bool

    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel

    @ViewBuilder
    var body: some View {
#if os(macOS) || os(visionOS)
        if isMaster && appWindowSizeModel.mode == .regular {
            GameElapsedTimerText(startDate: root.gameModel.startGameTime)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Spacer()
        }
#else
        Spacer()
#endif
    }
}

private struct OverlayGameMenuCloseFieldView: View {
    let marginWidth: CGFloat

    var body: some View {
        OverlayGameMenuCloseView(marginWidth: marginWidth)
            .foregroundStyle(.secondary)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))
    }
}

private struct OverlayGameMenuCloseView: View {
    let marginWidth: CGFloat

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        Button {
            gameScreenModel.showQuitGameAlert = true
        } label: {
            Image(systemName: "xmark.circle")
                .imageScale(valueFor(iOS: .large, macOS: .medium, tvOS: .small, visionOS: .large))
        }
        .borderLessTVButtonStyle()
        .frame(minWidth: 44, minHeight: 44)
        .padding(.horizontal, marginWidth)
        .accessibilityLabel(Text("Quit", bundle: .module))
    }
}

private struct OverlayGameMenuEnlargerView: View {
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.toggleSideBarWidth() }
        } label: {
            Image(systemName: gameScreenModel.isLargeSideBar ? "square.resize.down" : "square.resize.up")
                .imageScale(.large)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(
            gameScreenModel.isLargeSideBar
                ? Text("Reduce Sidebar", bundle: .module)
                : Text("Enlarge Sidebar", bundle: .module)
        )
    }
}

private struct OverlayGameMenuSecondOptionView: View {
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.resetToSettingsTab() }
        } label: {
            Image(systemName: NetworkModules.setting.icon)
        }
        .selectedBorderedStype(isSelected: gameScreenModel.showSettingTab != .none)
        .accessibilityLabel(Text(NetworkModules.setting.localizedTitle))
    }
}

private struct OverlayGameMenuToolIconView: View {
    let root: GameRoot
    let isMaster: Bool
    let marginWidth: CGFloat
    let onDisplayModeChange: (_ oldValue: GameMainTabDisplayMode, _ newValue: GameMainTabDisplayMode) -> Void
    let onToggle: (_ isShown: Bool) -> Void

    @ViewBuilder
    var body: some View {
#if os(macOS)
        if isMaster {
            OverlayGameMenuToolIconMacMasterView(marginWidth: marginWidth, onDisplayModeChange: onDisplayModeChange)
        } else {
            OverlayGameMenuToolIconMacPlayerView(root: root, marginWidth: marginWidth, onDisplayModeChange: onDisplayModeChange)
        }
#else
        // iOS and tvOS
        if isMaster {
            OverlayGameMenuToolIconIOSMasterView(onToggle: onToggle)
        } else {
            OverlayGameMenuToolIconIOSPlayerView(onToggle: onToggle)
        }
#endif
    }
}

private struct OverlayGameMenuToolIconMacMasterView: View {
    let marginWidth: CGFloat
    let onDisplayModeChange: (_ oldValue: GameMainTabDisplayMode, _ newValue: GameMainTabDisplayMode) -> Void

    @Environment(GameScreenModel.self) private var gameScreenModel

    @ViewBuilder
    var body: some View {
        @Bindable var gameScreenModel = gameScreenModel
        GameMainTabButtonView(isMaster: true, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            .padding(.horizontal, marginWidth)
            .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
                onDisplayModeChange(oldValue, newValue)
            }
    }
}

private struct OverlayGameMenuToolIconMacPlayerView: View {
    let root: GameRoot
    let marginWidth: CGFloat
    let onDisplayModeChange: (_ oldValue: GameMainTabDisplayMode, _ newValue: GameMainTabDisplayMode) -> Void

    @Environment(GameScreenModel.self) private var gameScreenModel

    @ViewBuilder
    var body: some View {
        @Bindable var gameScreenModel = gameScreenModel
        Group {
            if root.gameModel.gameType != .observer {
                GameMainTabButtonView(isMaster: false, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            }
        }
        .padding(.horizontal, marginWidth)
        .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
            onDisplayModeChange(oldValue, newValue)
        }
    }
}

// MARK: - iOS/tvOS Views

private struct OverlayGameMenuToolIconIOSMasterView: View {
    let onToggle: (_ isShown: Bool) -> Void

    @Environment(GameScreenModel.self) private var gameScreenModel

    @ViewBuilder
    var body: some View {
        @Bindable var gameScreenModel = gameScreenModel

        // Main game tab button (replaces firstOptionView)
        GameMainTabToggleButtonView(isMaster: true, isShown: $gameScreenModel.showMainTabIOS)
            .onChange(of: gameScreenModel.showMainTabIOS) { oldValue, newValue in
                onToggle(newValue)
            }

        // Settings button
        OverlayGameMenuSecondOptionView()
    }
}

private struct OverlayGameMenuToolIconIOSPlayerView: View {
    let onToggle: (_ isShown: Bool) -> Void

    @Environment(GameScreenModel.self) private var gameScreenModel

    @ViewBuilder
    var body: some View {
        @Bindable var gameScreenModel = gameScreenModel

        // Main game tab button (replaces firstOptionView)
        GameMainTabToggleButtonView(isMaster: false, isShown: $gameScreenModel.showMainTabIOS)
            .onChange(of: gameScreenModel.showMainTabIOS) { oldValue, newValue in
                onToggle(newValue)
            }

        // Settings button
        OverlayGameMenuSecondOptionView()
    }
}

private struct OverlayGameMenuWifiView: View {
    let root: GameRoot
    let isMaster: Bool
    let playerController: PlayerController?
    let marginWidth: CGFloat

    @ViewBuilder
    var body: some View {
        GameJoinCodeRevealButton(
            root: root,
            isMaster: isMaster,
            connectionStatus: (isMaster ? nil : playerController).map {
                GameConnectionStatusPresentation(
                    lostMaster: $0.gameModel.lostMaster,
                    sharePlayState: root.networkStore.sharePlayStore.connectionState,
                    isReconnecting: root.isLocalNetworkReconnecting
                )
            } ?? root.hostingStatus(isMaster: isMaster)
        )
        .imageScale(.small)
        .padding(.leading, marginWidth)
    }
}

#Preview("wide") {
    let root = GameRoot.previewFixture()
    VStack {
        OverlayGameMenu(
            root: root,
            playerController: PlayerController(root: root, asGameMaster: true),
            isMaster: true
        )
            .environment(GameScreenModel())
            .padding()
    }
    .background(Color.brown)
}

#Preview("small") {
    let root = GameRoot.previewFixture(game: .player)
    VStack {
        OverlayGameMenu(
            root: root,
            playerController: PlayerController(root: root, asGameMaster: false),
            isMaster: false
        )
            .environment(GameScreenModel())
            .frame(maxWidth: .infinity)
            .padding([.vertical])
            .padding(.trailing, 8)
    }
    .background(Color.brown)
}
