// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootSetupView: View {
    let root: GameRoot
    
    @Environment(AppSettingsModel.self) private var settingsModel
    @Environment(AppNavigationModel.self) private var appNavigationModel
#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    var body: some View {
        ZStack {
            MeshAnimationView()
                .ignoresSafeArea()
                .opacity(0.5)
            
            ScrollView {
#if os(macOS) || os(visionOS)
                Button {
                    withAnimation {
                        openWindow(id: WindowIdentifier.editor.rawValue)
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
            appNavigationModel.resetAppMode(isGame: root.gameModel.gameConfig.state == .started)
            if root.gameModel.gameConfig.state == .started {
                settingsModel.gameModus = root.gameModel.gameConfig.isMaster ? .master : .player
            } else {
                settingsModel.gameModus = .edit
            }
        }
    }
}

#Preview {
    GameRootSetupView(root: .preview)
        .environment(AppSettingsModel())
        .environment(AppNavigationModel())
}
