// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct TableCommands: Commands {
    public init(root: TableRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: TableRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "4")
    }
}

#endif
