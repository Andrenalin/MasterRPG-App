/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

/// The texts are localized from the module catalog. See CODE_AUDIT_29 §8.1.
struct EnvironmentHelpPageView: View {
    var body: some View {
        TutorialPageView(
            pageName: String(localized: "Environment", bundle: .module),
            imageName: "EnvironmentTips",
            imageCaption: String(localized: "Make sure you have even, good lighting and a stable environment for scanning. If scanning outdoors, cloudy days work best.", bundle: .module),
            prosTitle: String(localized: "Ideal Environment Characteristics", bundle: .module),
            pros: [
                String(localized: "Diffuse, consistent lighting", bundle: .module),
                String(localized: "Space around intended object", bundle: .module)
            ],
            consTitle: String(localized: "May Reduce Quality", bundle: .module),
            cons: [
                String(localized: "Sunny, directional lighting", bundle: .module),
                String(localized: "Inconsistent shadows", bundle: .module)
            ]
        )
    }
}

#Preview {
    EnvironmentHelpPageView()
}

#endif
