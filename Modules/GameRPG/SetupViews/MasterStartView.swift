// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import AdventureRPG

struct MasterStartView: View {
    let root: GameRoot
    
    @Environment(AppSettingsModel.self) private var settingsModel
    
    var sharePlayStore: RPGSharePlayController {
        root.networkStore.sharePlayStore
    }
    
    @State private var startSharePlayAnimation: Bool = false
    
    var body: some View {
        if root.gameModel.selectedGameMaster != nil && root.gameModel.selectedAdventure != nil {
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
            
            ImportDataModels(importController: root.adventureRoot.gameImportControllable, isSaveGame: true) {
                await startGame()
            }
            .padding()
        }
    }
    
    private var overlayAnimation: some View {
        Capsule()
        //RoundedRectangle(cornerRadius: 10)
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
        settingsModel.gameModus = .master
    }
}

#Preview {
    MasterStartView(root: .preview)
        .padding(30)
        .environment(AppSettingsModel())
}
