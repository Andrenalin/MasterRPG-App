// @copyright André Trettin

import AndrenalinKit
import RPGResources
import SwiftUI

extension Image {
    static func bundleImage(name: String) -> Image {
        guard let akImage = Image.loadImage(name: name) else {
            print("**** icon broken: \(name)")
            return Image(systemName: "exclamationmark.3")
        }
        return Image(akImage: akImage)
    }

    static func loadImage(name: String) -> AKImage? {
        #if os(macOS)
            return Bundle.module.image(forResource: name)
        #else
        let bundle = RPGResources.Resources.bundle
            return AKImage(named: name, in: bundle, with: nil)
        #endif
    }
}
