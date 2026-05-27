// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct TabRootView: View {
    let appModel: AppModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        layout
            .appExitNotifications(handler: appModel.adventureRoot.save)
            .onAppear {
                appModel.isCompactGameWindow = appSizeModel.mode == .compact
            }
            .onChange(of: appSizeModel.mode) { oldValue, newValue in
                appModel.isCompactGameWindow = newValue == .compact
                appModel.resetNavigation()
            }
    }

    private var layout: AppNavigationRouteType {
        valueFor(iOS: appSizeModel.mode == .compact ? .tabbed : .split, macOS: .tabbedSplit, tvOS: .tabbed, visionOS: .visionSplit)
    }
}

#Preview {
    TabRootView(appModel: .preview)
}
