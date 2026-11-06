// @copyright André Trettin

import CoreRPG
import SwiftUI
import MapRPG

public struct ExternalGameRootView: View {
    let root: GameRoot

    @Environment(\.appTheme) private var theme

    public init(root: GameRoot) {
        self.root = root
    }

    public var body: some View {
        VStack {
            if let playerController = root.gameModel.playerController {
                GameRootViewer(root: root, playerController: playerController, emptyTitle: "Waiting for Gamemaster", contentType: .externalPlayer)
                #if os(iOS) || os(visionOS)
                    .statusBarHidden()
                #endif
            } else {
                theme.backgroundGradient
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
        .environment(\.isSharedDisplay, true)
    }
}

#Preview {
    ExternalGameRootView(root: .preview)
}
