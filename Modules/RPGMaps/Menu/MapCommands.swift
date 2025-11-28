// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

#if !os(tvOS)
public struct MapCommands: Commands {
    public init(root: MapRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: MapRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "5")
    }
}

#endif
