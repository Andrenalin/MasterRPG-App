// @copyright André Trettin

#if os(iOS)  || os(visionOS) || os(tvOS)
import UIKit

final class IosAppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

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
        return false
    }
    #endif
}
#endif
