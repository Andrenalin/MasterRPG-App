// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct WeatherCommands: Commands {
    public init(root: WeatherRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: WeatherRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "0")
    }
}

#endif
