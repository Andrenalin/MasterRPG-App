// @copyright André Trettin

import CoreRPG
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct PhotoCommands: Commands {
    public init(root: PhotoRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: PhotoRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "8")
    }
}

#endif
