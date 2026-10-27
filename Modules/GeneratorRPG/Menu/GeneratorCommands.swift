// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct GeneratorCommands: Commands {
    public init(root: GeneratorRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: GeneratorRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "j")
    }
}

#endif
