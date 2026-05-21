// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct GeneratorCommands: Commands {
    public init(root: GeneratorRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: GeneratorRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "-")
    }
}

#endif
