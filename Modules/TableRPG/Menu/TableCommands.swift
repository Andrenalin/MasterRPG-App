// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftUI

#if !os(tvOS)
public struct TableCommands: Commands {
    public init(root: TableRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: TableRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "4")
    }
}

#endif
