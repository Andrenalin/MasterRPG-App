// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct InitialRootView: View {
    public init() {}
    
    @Environment(AppModel.self) private var appModel

    public var body: some View {
        // User activity handling has been moved to scene-level in MasterRPGApp
        // for better multi-window support on macOS and visionOS
        appModel.appNavigationModel.initialRouteType
    }
}

#Preview {
    InitialRootView()
        .frame(width: 400, height: 400)
}
