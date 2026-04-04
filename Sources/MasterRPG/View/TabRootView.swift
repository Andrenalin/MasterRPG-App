// @copyright André Trettin

import AdventureRPG
import CoreRPG
import RolePlayGameKit
import SwiftUI

struct TabRootView: View {
    let appModel: AppModel

    @Environment(\.appSizeMode) private var appSizeMode

    var body: some View {
        layout
            .appExitNotifications(handler: appModel.adventureRoot.save)
            .onChange(of: appSizeMode) { oldValue, newValue in
                appModel.resetNavigation()
            }
    }
    
    private var layout: AppRootType {
        valueFor(iOS: appSizeMode == .compact ? .tabbed : .split, macOS: .tabbedSplit, tvOS: .tabbed, visionOS: .tabbedExtSplit)
    }
}

#Preview {
    TabRootView(appModel: .preview)
}
