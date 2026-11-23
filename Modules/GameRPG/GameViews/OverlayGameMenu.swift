// @copyright André Trettin

#if os(iOS) || os(tvOS)
import CoreRPG
import AudioRPG
import Foundation
import SwiftUI

struct OverlayGameMenu: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
#if os(tvOS)
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
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `OverlayGameMenu` itself that all re-evaluated whenever any part
// of `OverlayGameMenu`'s body did.

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
#endif
