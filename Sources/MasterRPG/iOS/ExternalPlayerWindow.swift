// @copyright André Trettin

import RoleGameKit
import RPGGame
import SwiftUI

struct ExternalPlayerWindow: View {
    let appStore: AppStore

    var body: some View {
        VStack {
            if appStore.hasDatabase {
                ExternalGameRootView(root: appStore.gameRoot)
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
