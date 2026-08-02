// @copyright André Trettin

import CoreRPG
import SwiftUI
import TipKit

struct MasterStartView: View {
    let root: GameRoot
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator
    @Environment(\.supporterTier) private var supporterTier
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    var sharePlayStore: RPGSharePlayController {
        root.networkStore.sharePlayStore
    }
    
    @State private var startSharePlayAnimation: Bool = false
    
    var body: some View {
        if root.gameModel.selectedAdventure != nil {
            Button {
                Task {
                    await startGame()
                }
            } label: {
                Text(title(), bundle: .module)
                    .padding(8)
            }
            .overlay {
                overlayAnimation
            }
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.6).delay(1).repeatForever(autoreverses: false),
                value: startSharePlayAnimation
            )
            .onChange(of: sharePlayStore.canActivateSharePlay, initial: true) {
                startSharePlayAnimation = sharePlayStore.canActivateSharePlay
            }
            .popoverTip(
                navigator.isPresenting ? nil : MasterRPGTips.startOrJoinGame
            )
        }
    }
    
    private var overlayAnimation: some View {
        Capsule()
            .stroke(Color.accentColor, lineWidth: 4)
            .scaleEffect(startSharePlayAnimation && !accessibilityReduceMotion ? 2 : 1)
            .opacity(startSharePlayAnimation && !accessibilityReduceMotion ? 0 : 1)
            .accessibilityHidden(true)
    }
    
    @MainActor
    func title() -> LocalizedStringKey {
        if sharePlayStore.canActivateSharePlay {
            return "Share"
        } else {
            return "Start"
        }
    }
    
    @MainActor
    func startGame() async {
        await root.startMaster(supporterTier: supporterTier)
        guard root.gameModel.gameConfig.state == .started else {
            appGameStateModel.gameModus = .edit
            return
        }
        appGameStateModel.gameModus = .master
        await MasterRPGTips.donateGameStartedOrJoined()
    }
}

#Preview {
    MasterStartView(root: .preview)
        .padding(30)
        .environment(AppSettingsModel())
}
