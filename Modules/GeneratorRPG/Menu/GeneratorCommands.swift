// @copyright André Trettin

import CoreRPG
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct GeneratorCommands: Commands {
    public init(root: GeneratorRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: GeneratorRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "-")
    }
}

#endif
