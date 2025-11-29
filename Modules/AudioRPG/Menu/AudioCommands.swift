// @copyright André Trettin

import CoreRPG
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct AudioCommands: Commands {
    public init(root: AudioRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: AudioRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "6")
    }
}

#endif
