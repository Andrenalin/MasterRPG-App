// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

#if !os(tvOS)
public struct DiceCommands: Commands {
    public init(root: DiceRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: DiceRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "7")
    }
}

#endif
