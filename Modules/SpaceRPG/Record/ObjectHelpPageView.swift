/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

/// The texts are localized from the module catalog. See CODE_AUDIT_29 §8.1.
struct ObjectHelpPageView: View {
    var body: some View {
        TutorialPageView(
            pageName: String(localized: "Capturing Objects", bundle: .module),
            imageName: "ObjectCharacteristicsTips",
            imageCaption: String(localized: "Opaque, matte objects with varied surface textures scan best. Capture all sides of your object in a series of orbits.", bundle: .module),
            prosTitle: String(localized: "Ideal Object Characteristics", bundle: .module),
            pros: [
                String(localized: "Varied Surface Texture", bundle: .module),
                String(localized: "Non-reflective, matte surface", bundle: .module),
                String(localized: "Solid, opaque", bundle: .module)
            ],
            consTitle: String(localized: "May Reduce Quality", bundle: .module),
            cons: [
                String(localized: "Shiny materials", bundle: .module),
                String(localized: "Transparent, translucent objects", bundle: .module)
            ]
        )
    }
}

#Preview {
    ObjectHelpPageView()
}

#endif
