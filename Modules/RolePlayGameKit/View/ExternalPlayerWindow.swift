// @copyright André Trettin

import CoreRPG
import GameRPG
import SwiftUI

public struct ExternalPlayerWindow: View {
    public init(appModel: AppModel) {
        self.appModel = appModel
    }
    
    let appModel: AppModel
    
    @Environment(\.appTheme) private var theme

    public var body: some View {
        VStack {
            if appModel.appNavigationModel.initialRouteType == .ready {
                ExternalGameRootView(root: appModel.gameRoot)
                    .environmentSetUp(appModel)
                    .environmentActionSetUp(appModel)
            } else {
                theme.backgroundGradient
                    .overlay {
                        Text("Game is not running", bundle: .main)
                            .foregroundStyle(.white)
                            .font(.largeTitle)
                            .accessibilityAddTraits(.isHeader)
                    }
            }
        }
        .themedSurface()
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
