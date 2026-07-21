// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

public struct RuleCommands: Commands {
    public init(
        root: RuleRootModel,
        scenesManager: ScenesManager,
        routeActions: RouteActions
    ) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: RuleRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(
            root: root,
            scenesManager: scenesManager,
            routeActions: routeActions,
            key: "r"
        )
    }
}

#endif

