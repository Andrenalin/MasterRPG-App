/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import RealityKit
import SwiftUI

extension CaptureOverlayView {
    struct ManualShotButton: View {
        var session: ObjectCaptureSession

        var body: some View {
            Button {
                session.requestImageCapture()
            } label: {
                Label {
                    Text("Take Photo", bundle: .module)
                } icon: {
                    Image(systemName: "button.programmable")
                }
                .labelStyle(.iconOnly)
                .font(.largeTitle)
                .foregroundStyle(session.canRequestImageCapture ? .white : .gray)
            }
            .disabled(!session.canRequestImageCapture)
        }
    }
}

#Preview {
    CaptureOverlayView.ManualShotButton(session: ObjectCaptureSession())
        .padding()
        .background(.black)
}

#endif
