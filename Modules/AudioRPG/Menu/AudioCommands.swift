// @copyright André Trettin

import CoreRPG
import SwiftUI


#if !os(tvOS)
public struct AudioCommands: Commands {
    public init(root: AudioRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: AudioRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "6")
    }
}

#endif
