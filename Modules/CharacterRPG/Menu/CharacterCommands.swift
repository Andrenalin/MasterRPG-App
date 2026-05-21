// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct CharacterCommands: Commands {
    public init(root: CharacterRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: CharacterRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "2")
    }
}

#endif
