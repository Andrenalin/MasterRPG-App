/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct ReconstructionTitleView: View {
    var body: some View {
        Text(LocalizedString.processingTitle)
            .font(.largeTitle)
            .bold()
    }

    private enum LocalizedString {
        static let processingTitle = NSLocalizedString(
            "Processing title (Object Capture)",
            bundle: LocString.bundleForLocalizedStrings,
            value: "Processing",
            comment: "Title of processing view during processing phase."
        )
    }
}

#Preview {
    ReconstructionTitleView()
}

#endif
