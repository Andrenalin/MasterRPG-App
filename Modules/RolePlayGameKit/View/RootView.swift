// @copyright André Trettin

import CoreRPG
import SwiftUI

@MainActor
struct RootView: View {
    let appModel: AppModel
    
    var appMode: AppModeRouteType {
#if os(macOS) || os(tvOS)
        appModel.settingsModel.showGame ? .game : .gameSetup
#else
        appModel.settingsModel.showGame ? .game : .editor
#endif
    }
    
    var body: some View {
        appMode
    }
}

#Preview("Game") {
    RootView(appModel: .preview)
}
