// @copyright André Trettin

import SwiftUI
import RPGMaps

public struct ExternalGameRootView: View {
    let root: GameRoot

    public init(root: GameRoot) {
        self.root = root
    }

    public var body: some View {
        VStack {
            if let playerController = root.gameModel.playerController {
                GameRootViewer(root: root, playerController: playerController, emptyTitle: "Waiting for Gamemaster") { _ in
                    root.mapRoot.viewController.gameMapView(playerId: root.gameModel.gameConfig.id, external: true)
                }
                #if os(iOS) || os(visionOS)
                    .statusBar(hidden: true)
                #endif
            } else {
                Color.blue
                    .overlay {
                        Text("Game is not running", bundle: .module)
                            .foregroundStyle(.white)
                            .font(.largeTitle)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

struct ExternalGameView_Previews: PreviewProvider {
    static var previews: some View {
        ExternalGameRootView(root: .preview)
    }
}
