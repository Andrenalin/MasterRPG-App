// @copyright André Trettin

#if os(iOS) || os(visionOS) || os(tvOS)
import CoreRPG
import RolePlayGameKit
import os.log
import SwiftUI
import UIKit
import Observation

@MainActor @Observable
final class IosSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    public weak var windowScene: UIWindowScene?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else {
            return
        }

        if session.role == .windowExternalDisplayNonInteractive {
            window = UIWindow(windowScene: scene)
            let content = ExternalPlayerWindow(appModel: AppModel.shared)
            window?.rootViewController = UIHostingController(rootView: content)
            window?.isHidden = false
        }

#if os(visionOS)
        let preferences = UIWindowScene.GeometryPreferences.Vision()
        preferences.resizingRestrictions = UIWindowScene.ResizingRestrictions.freeform
        scene.requestGeometryUpdate(preferences)
#endif
        self.windowScene = scene

        for context in connectionOptions.urlContexts {
            handleIncomingURL(context.url)
        }
        for activity in connectionOptions.userActivities {
            handleUserActivity(activity)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            handleIncomingURL(context.url)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivity(userActivity)
    }

    private func handleIncomingURL(_ url: URL) {
        let appModel = AppModel.shared
        _ = RootURLHandler(appModel: appModel, role: .game)
            .handles(url, with: appModel.gameNavigator)
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        AppModel.shared.continueActivity(userActivity)
    }
}

extension IosSceneDelegate: AppWindowSceneModel {}

#endif
