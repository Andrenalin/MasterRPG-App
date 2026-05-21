// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct MapCommands: Commands {
    public init(root: MapRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: MapRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "5")
    }
}

#endif
