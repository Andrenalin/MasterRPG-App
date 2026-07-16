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
                    .environmentSetUp(appModel)
            } else {
                Color.blue
                    .overlay {
                        Text("Game is not running", bundle: .main)
                            .foregroundStyle(.white)
                            .font(.largeTitle)
                            .accessibilityAddTraits(.isHeader)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

#Preview("Game not running") {
    let appModel = {
        let model = AppModel()
        model.appNavigationModel.initialRouteType = .initializing
        return model
    }()

    ExternalPlayerWindow(appModel: appModel)
}
