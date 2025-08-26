// @copyright André Trettin

import CoreRPG
import SwiftData
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
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "8")
    }
}

#endif
