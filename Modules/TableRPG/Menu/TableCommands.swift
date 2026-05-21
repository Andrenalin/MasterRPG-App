// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct TableCommands: Commands {
    public init(root: TableRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: TableRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "4")
    }
}

#endif
