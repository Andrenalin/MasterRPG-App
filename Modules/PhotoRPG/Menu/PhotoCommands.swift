// @copyright André Trettin

import CoreRPG
import SwiftUI


#if !os(tvOS)
public struct PhotoCommands: Commands {
    public init(root: PhotoRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: PhotoRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "8")
    }
}

#endif
