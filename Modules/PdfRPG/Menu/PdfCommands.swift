// @copyright André Trettin

import CoreRPG
import SwiftUI


#if !os(tvOS)
public struct PdfCommands: Commands {
    public init(root: PdfRootModel, routeActions: RouteActions) {
        self.root = root
        self.routeActions = routeActions
    }

    let root: PdfRootModel
    let routeActions: RouteActions

    public var body: some Commands {
        ModuleCommands(root: root, routeActions: routeActions, key: "3")
    }
}

#endif
