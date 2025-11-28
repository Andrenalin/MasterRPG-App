// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

#if !os(tvOS)
public struct AdventureCommands: Commands {
    public init(root: AdventureRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: AdventureRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "1")
    }
}

#endif
