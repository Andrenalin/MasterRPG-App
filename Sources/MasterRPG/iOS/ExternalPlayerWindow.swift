// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import GameRPG
import SwiftUI

struct ExternalPlayerWindow: View {
    let appModel: AppModel

    var body: some View {
        VStack {
            if appModel.appNavigationModel.initialRouteType == .ready {
                ExternalGameRootView(root: appModel.gameRoot)
            } else {
                Color.blue
                    .overlay {
                        Text("Game is not running")
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
