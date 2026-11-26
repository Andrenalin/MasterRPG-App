// @copyright André Trettin

#if os(iOS)  || os(visionOS) || os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI

@MainActor @Observable final class IosAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

#if os(iOS) || os(visionOS)
    /// One background-task identifier per flush, so a second background entry can't
    /// overwrite (and leak) the assertion of a flush that is still running.
    private var backgroundFlushTasks: [UUID: UIBackgroundTaskIdentifier] = [:]

    /// `AppExitNotificationsViewModifier`'s resign-active save can be suspended
    /// mid-flight before it reaches disk. A background-task assertion buys the
    /// extra seconds the OS grants to actually finish the flush instead of racing
    /// suspension. Called from the app's aggregate `scenePhase == .background`:
    /// UIKit never calls `applicationDidEnterBackground` in a scene-based app.
    /// See CODE_AUDIT_17 §5.2 and CODE_AUDIT_18 §3.1.
    ///
    /// The assertion is held past the save as well, while Core Data checkpoints the WAL,
    /// updates the Spotlight index and exports to CloudKit: suspended while one of them holds
    /// the store's lock in the App Group container, the app is killed (`0xdead10cc`).
    func beginBackgroundFlush() {
        let token = UUID()
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "FlushPendingSaves") { [weak self] in
            self?.endBackgroundFlush(token)
        }
        guard taskId != .invalid else { return }
        backgroundFlushTasks[token] = taskId
        Task { @MainActor [weak self] in
            await AppModel.shared.save()
            await AppModel.shared.waitForPersistenceToSettle()
            self?.endBackgroundFlush(token)
        }
    }

    private func endBackgroundFlush(_ token: UUID) {
        guard let taskId = backgroundFlushTasks.removeValue(forKey: token) else { return }
        UIApplication.shared.endBackgroundTask(taskId)
    }
#endif

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        // The external display gets the configuration the Info.plist declares for it, with the
        // scene delegate that builds the player window. With `name: nil` and a delegate only
        // for the application role that entry was never used. See CODE_AUDIT_21 §5.26.
        let isExternalDisplay = role == .windowExternalDisplayNonInteractive
        let sceneConfig = UISceneConfiguration(
            name: isExternalDisplay ? "External Game View" : nil,
            sessionRole: role
        )
        if role == .windowApplication || isExternalDisplay {
            sceneConfig.delegateClass = IosSceneDelegate.self
        }
        return sceneConfig
    }
}
#endif
