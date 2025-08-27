// @copyright André Trettin

import AndrenalinKit
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

            #if INTERNAL_APP
                return AKImage(named: name)
            #else
                return Bundle.module.image(forResource: name)
            #endif

        #else

            #if INTERNAL_APP
                let bundle = Bundle.main
            #else
                let bundle = Bundle.module
            #endif
            return AKImage(named: name, in: bundle, with: nil)

        #endif
    }
}
