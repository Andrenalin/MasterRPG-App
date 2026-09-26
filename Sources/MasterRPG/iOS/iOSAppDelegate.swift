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
    func beginBackgroundFlush() {
        let token = UUID()
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "FlushPendingSaves") { [weak self] in
            self?.endBackgroundFlush(token)
        }
        guard taskId != .invalid else { return }
        backgroundFlushTasks[token] = taskId
        Task { @MainActor [weak self] in
            await AppModel.shared.save()
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
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            sceneConfig.delegateClass = IosSceneDelegate.self
        }
        return sceneConfig
    }
}
#endif
