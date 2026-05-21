// @copyright André Trettin

import CoreRPG
import SwiftUI


#if !os(tvOS)
public struct PdfCommands: Commands {
    public init(root: PdfRootModel, scenesManager: ScenesManager, routeActions: RouteActions) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
    }

    let root: PdfRootModel
    let scenesManager: ScenesManager
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, scenesManager: scenesManager, routeActions: routeActions, key: "3")
    }
}

#endif
