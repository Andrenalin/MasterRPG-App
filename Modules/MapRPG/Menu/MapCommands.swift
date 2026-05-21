// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct MapCommands: Commands {
    public init(root: MapRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: MapRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "5")
    }
}

#endif
