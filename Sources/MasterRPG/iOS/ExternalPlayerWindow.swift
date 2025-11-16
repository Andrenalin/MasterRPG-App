// @copyright André Trettin

import RoleGameKit
import RPGGame
import SwiftUI

struct ExternalPlayerWindow: View {
    let appModel: AppModel

    var body: some View {
        VStack {
            if appModel.hasDatabase {
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
