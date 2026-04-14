// @copyright André Trettin

#if os(iOS) || os(visionOS) || os(tvOS)
import CoreRPG
import RolePlayGameKit
import os.log
import SwiftUI
import UIKit

@Observable final class IosSceneDelegate: NSObject, UIWindowSceneDelegate, AppWindowSceneModel {
    var window: UIWindow?
    weak var windowScene: UIWindowScene?

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
    }
}

#endif
