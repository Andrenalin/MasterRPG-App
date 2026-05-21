// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct DiceCommands: Commands {
    public init(root: DiceRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: DiceRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "7")
    }
}

#endif
