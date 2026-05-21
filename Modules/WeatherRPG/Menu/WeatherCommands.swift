// @copyright André Trettin

import CoreRPG

import SwiftUI

#if !os(tvOS)
public struct WeatherCommands: Commands {
    public init(root: WeatherRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: WeatherRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "0")
    }
}

#endif
