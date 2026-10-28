// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
/// Not used on purpose: the generator has no list of its own, its views are inlined in the modules
/// that need them, so `MenuCommandList` leaves these commands out. Kept until the final version of
/// the generator. See CODE_AUDIT_Since_3.0.1 §5.3.
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
