// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootTabItemView: View {
    let root: GameRootController

#if os(macOS)
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
    }
}

//#Preview {
//    GameRootTabItemView(root: .preview)
//        .environment(\.wideMode, .small)
//        .environment(AppSettingsModel())
//        .environment(SelectionSheetLinkModel())
//}
