// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootSetupView: View {
    let root: GameRoot
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(ScenesManager.self) private var sceneManager
    
    var body: some View {
        ZStack {
            MeshAnimationView()
                .ignoresSafeArea()
                .opacity(0.5)
            
            ScrollView {
#if os(macOS) || os(visionOS)
                Button {
                    withAnimation {
                        sceneManager.openWindow(SceneId.editor)
                    }
                } label: {
                    Label { Text("Editor Window", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
#endif
                
                GameOptionView(root: root)
            }
            .task {
                await root.networkStore.setup(gameModel: root.gameModel)
            }
        }
        .onChange(of: root.gameModel.gameConfig.state, initial: true) {
            appGameStateModel.isGameRunning = root.gameModel.gameConfig.state == .started
            if root.gameModel.gameConfig.state == .started {
                appGameStateModel.gameModus = root.gameModel.gameConfig.isMaster ? .master : .player
            } else {
                appGameStateModel.gameModus = .edit
            }
            root.widgetGameRunningChanged()
        }
    }
}

#Preview {
    GameRootSetupView(root: .preview)
        .environment(AppSettingsModel())
        .environment(AppNavigationModel(appGameStateModel: AppGameStateModel()))
}
