// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG
import TipKit

struct MasterStartView: View {
    let root: GameRoot
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator
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
            
#if !os(tvOS)
            SharePlayButton("Play RPG Online", activity: RPGActivity())
                .opacity(startSharePlayAnimation ? 0 : 1)
                .allowsHitTesting(!startSharePlayAnimation)
                .accessibilityHidden(startSharePlayAnimation)
#endif
            
            Button {
                navigator.navigate(to: ImportRoute.importGame, method: .managedSheet)
            } label: {
                Label { Text("Import Saved Game", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
            }
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
        await root.startMaster()
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
