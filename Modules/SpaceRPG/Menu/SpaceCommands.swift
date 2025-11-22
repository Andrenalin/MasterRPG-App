// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct SpaceCommands: Commands {
    public init(root: SpaceRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: SpaceRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "9")
    }
}

#endif
