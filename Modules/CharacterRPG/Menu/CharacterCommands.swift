// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct CharacterCommands: Commands {
    public init(root: CharacterRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: CharacterRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "2")
    }
}

#endif
