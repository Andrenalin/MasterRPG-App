// @copyright André Trettin

import CoreRPG
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct CharacterCommands: Commands {
    public init(root: CharacterRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: CharacterRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "2")
    }
}

#endif
