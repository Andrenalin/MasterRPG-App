// @copyright André Trettin

import CoreRPG
import SwiftUI


#if !os(tvOS)
public struct AudioCommands: Commands {
    public init(root: AudioRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions

    }

    let root: AudioRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "6")
    }
}

#endif
