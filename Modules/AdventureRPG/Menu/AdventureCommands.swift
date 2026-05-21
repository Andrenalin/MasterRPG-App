// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct AdventureCommands: Commands {
    public init(root: AdventureRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: AdventureRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "1")
    }
}

#endif
