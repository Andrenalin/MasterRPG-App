// @copyright André Trettin

import CoreRPG
import CharacterRPG
import SwiftUI

struct PlayerStartView: View {
    let root: GameRoot
    
    var sharePlayStore: RPGSharePlayController {
        root.networkStore.sharePlayStore
    }
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    @State private var startSharePlayAnimation: Bool = false
    
    var body: some View {
        if root.characterRoot.linkControllable.validateLink(itemId: root.gameModel.selectedCharacter ?? UUID()) {
            Group {
                if sharePlayStore.canActivateSharePlay {
                    Button {
                        appGameStateModel.gameModus = .player

                        Task {
                            await root.startGame(to: nil, mode: .player)
                        }
                    } label: {
                        Label {
                            Text(root.gameModel.gameConfig.state == .stopped ? "Join Game" : "Cancel Game", bundle: .module)
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .imageScale(.large)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
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
#if os(tvOS)
                    .padding(.top, 24)
#endif
                    .padding(.bottom, 16)
                } else {
                    if let playerNetworkController = root.networkStore.model.playerStore {
                        BrowserView(root: root, playerNetworkControllable: playerNetworkController)
                            .onChange(of: playerNetworkController.networkModel.isConnected) {
                                if playerNetworkController.networkModel.isConnected {
                                    appGameStateModel.gameModus = .player

                                } else {
                                    appGameStateModel.gameModus = .edit
                                }
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
