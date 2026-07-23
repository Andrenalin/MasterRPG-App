// @copyright André Trettin

#if os(macOS)
import AppKit
import CoreRPG
import RolePlayGameKit

@MainActor @Observable final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == UserActivity.bundleIdentifierType else { return false }
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return false }

        AppModel.shared.routeToModuleWhenReady(
            module,
            itemId: itemId,
            entryId: UserActivity.childId(from: userActivity)
        )
        return true
    }
}

#endif
