// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct AudioCommands: Commands {
    public init(root: AudioRoot, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: AudioRoot
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "6")
    }
}

#endif
