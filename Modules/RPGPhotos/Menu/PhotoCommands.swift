// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct PhotoCommands: Commands {
    public init(root: PhotoRoot, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: PhotoRoot
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "8")
    }
}

#endif
