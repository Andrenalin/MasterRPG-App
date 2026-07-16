/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import RealityKit
import SwiftUI

@MainActor
struct BoundingBoxGuidanceView: View {
    var session: ObjectCaptureSession
    var hasDetectionFailed: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack {
            if let guidanceText {
                Text(guidanceText)
                    .font(.callout)
                    .bold()
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: horizontalSizeClass == .regular ? 400 : 360)
            }
        }
    }

    private var guidanceText: String? {
        if case .ready = session.state {
            if hasDetectionFailed {
                return NSLocalizedString(
                    "Can‘t find your object. It should be larger than 3in (8cm) in each dimension.",
                    bundle: LocString.bundleForLocalizedStrings,
                    value: "Can‘t find your object. It should be larger than 3in (8cm) in each dimension.",
                    comment: "Feedback message when detection has failed."
                )
            }

            return NSLocalizedString(
                "Move close and center the dot on your object, then tap Continue. (Object Capture, State)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Move close and center the dot on your object, then tap Continue.",
                comment: "Feedback message to fill camera feed with object."
            )
        } else if case .detecting = session.state {
            return NSLocalizedString(
                "Move around to ensure that the whole object is inside the box. Drag handles to manually resize. (Object Capture, State)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Move around to ensure that the whole object is inside the box. Drag handles to manually resize.",
                comment: "Feedback message to size box to object."
            )
        }

        return nil
    }
}

#Preview {
    BoundingBoxGuidanceView(session: ObjectCaptureSession(), hasDetectionFailed: false)
        .padding()
        .background(.black)
}

#endif
