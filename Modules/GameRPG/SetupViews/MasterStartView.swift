// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG

struct MasterStartView: View {
    let root: GameRoot
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator
    
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
            .animation(.easeOut(duration: 0.6).delay(1).repeatForever(autoreverses: false), value: startSharePlayAnimation)
            .onChange(of: sharePlayStore.canActivateSharePlay, initial: true) {
                startSharePlayAnimation = sharePlayStore.canActivateSharePlay
            }
            
#if !os(tvOS)
            SharePlayButton("Play RPG Online", activity: RPGActivity())
                .opacity(startSharePlayAnimation ? 0 : 1)
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
            .scaleEffect(startSharePlayAnimation ? 2 : 1)
            .opacity(startSharePlayAnimation ? 0 : 1)
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
        appGameStateModel.gameModus = .master
    }
}

#Preview {
    MasterStartView(root: .preview)
        .padding(30)
        .environment(AppSettingsModel())
}
