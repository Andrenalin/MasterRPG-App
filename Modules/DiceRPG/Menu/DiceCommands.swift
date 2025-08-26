// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct DiceCommands: Commands {
    public init(root: DiceRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: DiceRootModel
    let navigator: Navigator
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "7")
    }
}

#endif
