/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import RealityKit
import SwiftUI

extension CaptureOverlayView {
    struct NumOfImagesButton: View {
        var session: ObjectCaptureSession

        var body: some View {
            VStack(spacing: 8) {
                Text(Image(systemName: "photo"))

                Text(
                    verbatim: "\(session.numberOfShotsTaken.formatted())/\(session.maximumNumberOfInputImages.formatted())"
                )
                .font(.footnote)
                .fontWidth(.condensed)
                .fontDesign(.rounded)
                .bold()
            }
            .foregroundStyle(session.feedback.contains(.overCapturing) ? .red : .white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Captured photos", bundle: .module))
            .accessibilityValue(
                Text(
                    "\(session.numberOfShotsTaken) of \(session.maximumNumberOfInputImages)",
                    bundle: .module
                )
            )
        }
    }
}

#Preview {
    CaptureOverlayView.NumOfImagesButton(session: ObjectCaptureSession())
        .padding()
        .background(.black)
}

#endif
