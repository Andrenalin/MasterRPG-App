// @copyright André Trettin

import CoreRPG
import CharacterRPG
import SwiftUI

struct PlayerStartView: View {
    let root: GameRootController
    
    var sharePlayStore: RPGSharePlayController {
        root.networkStore.sharePlayStore
    }
    
    @Environment(AppSettingsModel.self) private var settingsModel
    
    @State private var startSharePlayAnimation: Bool = false
    
    var body: some View {
//        if root.characterRoot.linkController.validate(id: root.gameModel.selectedCharacter, isCharacter: true) != nil {
            Group {
                if sharePlayStore.canActivateSharePlay {
                    Button {
                        Task {
                            await root.startGame(to: nil, mode: .player)
                        }
                    settingsModel.gameModus = .player
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
                            .scaleEffect(startSharePlayAnimation ? 2 : 1)
                            .opacity(startSharePlayAnimation ? 0 : 1)
                    )
                    .animation(.easeOut(duration: 0.6).delay(1).repeatForever(autoreverses: false), value: startSharePlayAnimation)
                    .onAppear { startSharePlayAnimation.toggle() }
#if os(tvOS)
                    .padding(.top, 24)
#endif
                    .padding(.bottom, 16)
                } else {
                    if let playerNetworkController = root.networkStore.model.playerStore {
                        BrowserView(root: root, playerNetworkControllable: playerNetworkController)
                            .onChange(of: playerNetworkController.networkModel.isConnected) {
                                if playerNetworkController.networkModel.isConnected {
                                    settingsModel.gameModus = .player
                                } else {
                                    settingsModel.gameModus = .edit
                                }
                            }
                    }
                }
            }
//        }
    }
}

