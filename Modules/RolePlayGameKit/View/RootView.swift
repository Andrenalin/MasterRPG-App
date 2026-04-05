// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor
struct RootView: View {
    let appModel: AppModel
        
    var body: some View {
        appModel.appNavigationModel.modeRouteType
    }
}

#Preview("Game") {
    RootView(appModel: .preview)
}
