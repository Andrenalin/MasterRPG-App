// @copyright André Trettin

#if os(macOS)
import AppKit
import CoreRPG
import os.log
import RolePlayGameKit

@MainActor @Observable final class MacAppDelegate: NSObject, NSApplicationDelegate {
    // Posting `willTerminateNotification` doesn't block termination, so the async
    // flush `AppExitNotificationsViewModifier` starts from it can be cut off by the
    // process exiting before the `Task` runs (Cmd-Q loses up to a minute of queued
    // edits). Returning `.terminateLater` here and replying only once the flush has
    // actually completed closes that window. See CODE_AUDIT_17 §5.2.
    //
    // The reply is bounded by `terminationSaveDeadline`: a save stuck on file
    // coordination or a Core Data `perform` must not leave Cmd-Q without effect
    // (the user would force-quit and lose the edits anyway). See CODE_AUDIT_18 §3.11.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        hasRepliedToTermination = false
        Task { @MainActor [weak self] in
            await AppModel.shared.save()
            self?.replyToTermination()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.terminationSaveDeadline)
            guard let self, !self.hasRepliedToTermination else { return }
            Logger.appDelegate.error("Save did not finish within \(Self.terminationSaveDeadline, privacy: .public); quitting anyway")
            self.replyToTermination()
        }
        return .terminateLater
    }

    private static let terminationSaveDeadline: Duration = .seconds(5)
    private var hasRepliedToTermination = false

    private func replyToTermination() {
        guard !hasRepliedToTermination else { return }
        hasRepliedToTermination = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        return AppModel.shared.continueActivity(userActivity)
    }
}


private extension Logger {
    static let appDelegate = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MasterRPG", category: "MacAppDelegate")
}
#endif
