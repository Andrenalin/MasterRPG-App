// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct PdfCommands: Commands {
    public init(root: PdfRoot, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: PdfRoot
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "3")
    }
}

#endif
