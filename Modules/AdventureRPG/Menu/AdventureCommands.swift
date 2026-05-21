// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct AdventureCommands: Commands {
    public init(root: AdventureRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: AdventureRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "1")
    }
}

#endif
