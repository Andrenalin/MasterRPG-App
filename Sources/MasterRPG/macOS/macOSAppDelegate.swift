// @copyright André Trettin

#if os(macOS)
import AppKit
import CoreRPG
import RolePlayGameKit

@MainActor @Observable final class MacAppDelegate: NSObject, NSApplicationDelegate {
    // Posting `willTerminateNotification` doesn't block termination, so the async
    // flush `AppExitNotificationsViewModifier` starts from it can be cut off by the
    // process exiting before the `Task` runs (Cmd-Q loses up to a minute of queued
    // edits). Returning `.terminateLater` here and replying only once the flush has
    // actually completed closes that window. See CODE_AUDIT_17 §5.2.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppModel.shared.save()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

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
