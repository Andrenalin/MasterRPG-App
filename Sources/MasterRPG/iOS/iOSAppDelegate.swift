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
    private var backgroundFlushTaskId: UIBackgroundTaskIdentifier = .invalid

    /// `AppExitNotificationsViewModifier`'s resign-active save can be suspended
    /// mid-flight before it reaches disk. A background-task assertion buys the
    /// extra seconds the OS grants to actually finish the flush instead of racing
    /// suspension. See CODE_AUDIT_17 §5.2.
    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundFlushTaskId = application.beginBackgroundTask(withName: "FlushPendingSaves") { [weak self] in
            guard let self else { return }
            application.endBackgroundTask(self.backgroundFlushTaskId)
            self.backgroundFlushTaskId = .invalid
        }
        guard backgroundFlushTaskId != .invalid else { return }
        Task { @MainActor [weak self] in
            await AppModel.shared.save()
            guard let self, self.backgroundFlushTaskId != .invalid else { return }
            application.endBackgroundTask(self.backgroundFlushTaskId)
            self.backgroundFlushTaskId = .invalid
        }
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
    
#if os(iOS)
    func application(_ application: UIApplication, handleOpen url: URL) -> Bool {
        let appModel = AppModel.shared
        return RootURLHandler(appModel: appModel, role: .game)
            .handles(url, with: appModel.gameNavigator)
    }
#endif
}
#endif
