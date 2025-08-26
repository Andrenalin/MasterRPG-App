// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct PdfCommands: Commands {
    public init(root: PdfRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: PdfRootModel
    let navigator: Navigator
    
    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "3")
    }
}

#endif
