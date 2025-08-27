// @copyright André Trettin

import CoreRPG
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct WeatherCommands: Commands {
    public init(root: WeatherRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: WeatherRootModel
    let navigator: Navigator

    public var body: some Commands {
        ModuleCommands(root: root, navigator: navigator, key: "0")
    }
}

#endif
