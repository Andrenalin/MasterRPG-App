// @copyright André Trettin

import CoreRPG
import SwiftUI


#if !os(tvOS)
public struct SpaceCommands: Commands {
    public init(root: SpaceRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: SpaceRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "9")
    }
}

#endif
