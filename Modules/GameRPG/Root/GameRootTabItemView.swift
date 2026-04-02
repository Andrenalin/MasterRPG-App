// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootTabItemView: View {
    let root: GameRoot
    
#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    var body: some View {
        GameRootTabView(root: root)
    }
}

struct GameRootTabView: View {
    let root: GameRoot

    @Environment(AppSettingsModel.self) private var settingsModel

#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    var body: some View {
        ZStack {
            MeshAnimationView()
                .ignoresSafeArea()
                .opacity(0.5)
            
            ScrollView {
#if os(macOS)
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
            settingsModel.showGame <=> root.gameModel.gameConfig.state == .started
            if root.gameModel.gameConfig.state == .started {
                settingsModel.gameModus = root.gameModel.gameConfig.isMaster ? .master : .player
            } else {
                settingsModel.gameModus = .edit
            }
        }
    }
}

#Preview {
    GameRootTabItemView(root: .preview)
        .environment(\.wideMode, .small)
        .environment(AppSettingsModel())
}
