// @copyright André Trettin

#if os(iOS) || os(visionOS) || os(tvOS)
import AndrenalinKit
import Combine
import CloudKit
import RolePlayGameKit
import GameRPG
import os.log
import SwiftUI
import UIKit

final class IosSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    var originalDelegate: (any UIWindowSceneDelegate)?
    var window: UIWindow?

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
    }
}

@MainActor
final class GameShare {
    static var root: GameRoot?
}

#endif
