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
        OverlayGameMenuTvMenuView(root: root, isMaster: isMaster, playerController: playerController, marginWidth: marginWidth)
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

    /// Handles the simple show/hide toggle for iOS/tvOS
    func handleMainTabToggle(isShown: Bool, isMaster: Bool) {
        // Save the state to UserDefaults
        if isMaster {
            appSettingsModel.autoShowMasterMainTab = isShown
        } else {
            appSettingsModel.autoShowPlayerMainTab = isShown
        }

        // Update the display
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            if isShown {
                gameScreenModel.showMainTab = isMaster ? .game : .value
            } else {
                gameScreenModel.showMainTab = .none
            }
        }
    }

    /// Handles the three-state main tab display mode changes
    func handleMainTabDisplayModeChange(oldValue: GameMainTabDisplayMode, newValue: GameMainTabDisplayMode, isMaster: Bool) {
        // Save the display mode to UserDefaults
        if isMaster {
            appSettingsModel.masterMainTabDisplayMode = newValue.rawValue
        } else {
            appSettingsModel.playerMainTabDisplayMode = newValue.rawValue
        }

        switch newValue {
        case .hidden:
            // Hide the game view
            gameScreenModel.showMainTab = .none

            // Close the appropriate window if it was open
            if isMaster {
                // Master: Close adventure viewer window
                if scenesManager.getSceneState(for: SceneId.adventureViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.adventureViewer)
                }
            } else {
                // Player: Close character viewer window
                if scenesManager.getSceneState(for: SceneId.valueViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.valueViewer)
                }
            }

        case .inline:
            // Show game view inline
            gameScreenModel.showMainTab = isMaster ? .game : .value

            // Close the window if it was open
            if isMaster {
                if scenesManager.getSceneState(for: SceneId.adventureViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.adventureViewer)
                }
            } else {
                if scenesManager.getSceneState(for: SceneId.valueViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.valueViewer)
                }
            }

        case .window:
            // Hide inline view
            gameScreenModel.showMainTab = .none

            // Open as separate window with appropriate content
            #if os(macOS) || os(visionOS)
            if isMaster {
                // Master: Open adventure viewer with current adventure
                if scenesManager.getSceneState(for: SceneId.adventureViewer) == .closed, let adventureId = root.gameModel.selectedAdventure {
                    scenesManager.openWindow(SceneId.viewerId(for: .adventure), selection: WindowItemSelection(itemId: adventureId))
                }
            } else {
                // Player: Open character viewer with current character
                if scenesManager.getSceneState(for: SceneId.valueViewer) == .closed, let characterId = root.gameModel.selectedCharacter {
                    scenesManager.openWindow(SceneId.viewerId(for: .value), selection: WindowItemSelection(itemId: characterId))
                }
            }
            #endif
        }
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

                OverlayGameMenuWifiView(root: root, isMaster: isMaster, playerController: playerController, marginWidth: marginWidth)

                GameTableWindowButton(root: root, isMaster: isMaster)
                    .padding(.leading, 32)
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
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))

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

    var body: some View {
        HStack {
            if isMaster || root.gameModel.gameType != .observer {
                GameDiceToggleButton()
            }
            Spacer()
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
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
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
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
#if os(macOS) || os(visionOS)
            scenesManager.openWindow(SceneId.logs)
#else
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.resetToSettingsTab() }
#endif
        } label: {
            Image(systemName: NetworkModules.setting.icon)
        }
        .selectedBorderedStype(isSelected: gameScreenModel.showSettingTab != .none)
#if os(macOS) || os(visionOS)
        .accessibilityLabel(Text("Logs", bundle: .module))
#else
        .accessibilityLabel(Text(NetworkModules.setting.localizedTitle))
#endif
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
