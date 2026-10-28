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
                // Only a real layout swap (iPhone/iPad tabbed ↔ split) loses the route. On Mac and
                // visionOS the layout stays, and re-navigating popped a pushed detail.
                // See CODE_AUDIT_Since_3.0.1 §5.16.
                if Self.layout(for: oldValue) != Self.layout(for: newValue) {
                    appModel.rememberRouteForLayoutChange()
                }
                appModel.isCompactGameWindow = newValue == .compact
            }
            .task(id: appModel.layoutRestoreTarget) {
                guard appModel.layoutRestoreTarget != nil else { return }
                try? await Task.sleep(for: NavigationTiming.layoutChangeSettleDelay)
                guard !Task.isCancelled else { return }
                appModel.restoreRouteAfterLayoutChange(isCompact: appSizeModel.mode == .compact)
            }
    }

    private var layout: AppNavigationRouteType {
        Self.layout(for: appSizeModel.mode)
    }

    static func layout(for mode: AppSizeMode) -> AppNavigationRouteType {
#if os(iOS)
        mode == .compact ? .tabbed : .split
#elseif os(macOS)
        .tabbedSplit
#elseif os(tvOS)
        .tabbed
#else
        .split
#endif
    }
}

#Preview {
    TabRootView(appModel: .preview)
        .environment(AppWindowSizeModel())
}
