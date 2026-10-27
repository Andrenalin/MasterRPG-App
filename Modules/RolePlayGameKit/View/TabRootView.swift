// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TabRootView: View {
    let appModel: AppModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        layout
            .onAppear {
                appModel.isCompactGameWindow = appSizeModel.mode == .compact
            }
            .onChange(of: appSizeModel.mode) { oldValue, newValue in
                appModel.rememberRouteForLayoutChange()
                appModel.isCompactGameWindow = newValue == .compact
            }
            .task(id: appModel.layoutRestoreTarget) {
                guard appModel.layoutRestoreTarget != nil else { return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                appModel.restoreRouteAfterLayoutChange(isCompact: appSizeModel.mode == .compact)
            }
    }

    private var layout: AppNavigationRouteType {
        valueFor(iOS: appSizeModel.mode == .compact ? .tabbed : .split, macOS: .tabbedSplit, tvOS: .tabbed, visionOS: .split)
    }
}

#Preview {
    TabRootView(appModel: .preview)
        .environment(AppWindowSizeModel())
}
