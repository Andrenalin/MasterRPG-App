// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct DiceCommands: Commands {
    public init(root: DiceRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: DiceRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "7")
    }
}

#endif
