// @copyright André Trettin

import CoreRPG
import SwiftUI


#if !os(tvOS)
public struct PhotoCommands: Commands {
    public init(root: PhotoRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: PhotoRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "8")
    }
}

#endif
