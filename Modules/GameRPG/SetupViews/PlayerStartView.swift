// @copyright André Trettin

import CoreRPG
import CharacterRPG
import SwiftUI
import TipKit

enum PlayerJoinTransport: Hashable, Sendable {
    case sharePlay
    case localNetwork
}

struct PlayerJoinOptions: Sendable {
    let availableTransports: Set<PlayerJoinTransport>

    init(canActivateSharePlay: Bool, hasLocalNetwork: Bool) {
        var transports: Set<PlayerJoinTransport> = []
        if canActivateSharePlay {
            transports.insert(.sharePlay)
        }
        if hasLocalNetwork {
            transports.insert(.localNetwork)
        }
        availableTransports = transports
    }
}

struct PlayerStartView: View {
    let root: GameRoot
    
    var sharePlayStore: RPGSharePlayController {
        root.networkStore.sharePlayStore
    }
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator
    @Environment(\.supporterTier) private var supporterTier
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    @State private var startSharePlayAnimation: Bool = false
    
    var body: some View {
        if root.characterRoot.linkControllable.validateLink(itemId: root.gameModel.selectedCharacter ?? UUID()) {
            let playerNetworkController = root.networkStore.model.playerStore
            let joinOptions = PlayerJoinOptions(
                canActivateSharePlay: sharePlayStore.canActivateSharePlay,
                hasLocalNetwork: playerNetworkController != nil
            )

            VStack {
                if joinOptions.availableTransports.contains(.sharePlay) {
                    Text("SharePlay", bundle: .module)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                    Button {
                        appGameStateModel.gameModus = .player

                        Task {
                            await root.startGame(
                                to: nil,
                                mode: .player,
                                supporterTier: supporterTier
                            )
                            guard root.gameModel.gameConfig.state == .started else { return }
                            await MasterRPGTips.donateGameStartedOrJoined()
                        }
                    } label: {
                        Label {
                            Text("Join Game", bundle: .module)
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .imageScale(.large)
                        }
                        .padding()
                    }
                    .borderLessTVButtonStyle()
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor, lineWidth: 4)
                            .scaleEffect(startSharePlayAnimation && !accessibilityReduceMotion ? 2 : 1)
                            .opacity(startSharePlayAnimation && !accessibilityReduceMotion ? 0 : 1)
                            .accessibilityHidden(true)
                    )
                    .animation(
                        accessibilityReduceMotion ? nil : .easeOut(duration: 0.6).delay(1).repeatForever(autoreverses: false),
                        value: startSharePlayAnimation
                    )
                    .onAppear { startSharePlayAnimation = true }
                    .popoverTip(
                        navigator.isPresenting ? nil : MasterRPGTips.startOrJoinGame
                    )
#if os(tvOS)
                    .padding(.top, 24)
#endif
                    .padding(.bottom, 16)
                }

                if joinOptions.availableTransports.contains(.localNetwork), let playerNetworkController {
                    BrowserView(root: root, playerNetworkControllable: playerNetworkController)
                        .onChange(of: playerNetworkController.networkModel.isConnected) {
                            if playerNetworkController.networkModel.isConnected {
                                appGameStateModel.gameModus = .player
                                Task {
                                    await MasterRPGTips.donateGameStartedOrJoined()
                                }
                            } else {
                                appGameStateModel.gameModus = .edit
                            }
                        }
                }
            }
        }
    }
}

#Preview {
    PlayerStartView(root: .preview)
        .environment(AppGameStateModel())
        .environment(ScenesManager())
}
