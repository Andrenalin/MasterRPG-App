/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct ObjectHelpPageView: View {
    var body: some View {
        TutorialPageView(
            pageName: "Capturing Objects",
            imageName: "ObjectCharacteristicsTips",
            imageCaption: "Opaque, matte objects with varied surface textures scan best. Capture all sides of your object in a series of orbits.\n",
            prosTitle: "Ideal Object Characteristics",
            pros: [
                "Varied Surface Texture",
                "Non-reflective, matte surface",
                "Solid, opaque"
            ],
            consTitle: "May Reduce Quality",
            cons: [
                "Shiny materials",
                "Transparent, transluscent objects"
            ]
        )
    }
}

#Preview {
    ObjectHelpPageView()
}

#endif
