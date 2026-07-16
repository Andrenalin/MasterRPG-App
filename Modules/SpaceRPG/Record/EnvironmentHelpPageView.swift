/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct EnvironmentHelpPageView: View {
    var body: some View {
        TutorialPageView(
            pageName: "Environment",
            imageName: "EnvironmentTips",
            imageCaption: "Make sure you have even, good lighting and a stable environment for scanning. If scanning outdoors, cloudy days work best.\n",
            prosTitle: "Ideal Environment Characteristics",
            pros: [
                "Diffuse, consistent lighting",
                "Space around intended object",
                " "
            ],
            consTitle: "May Reduce Quality",
            cons: [
                "Sunny, directional lighting",
                "Inconsistent shadows"
            ]
        )
    }
}

#Preview {
    EnvironmentHelpPageView()
}

#endif
