/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import RealityKit
import SwiftUI
import os

extension CaptureOverlayView {
    @MainActor
    struct CaptureButton: View {
        var session: ObjectCaptureSession
        var isObjectFlipped: Bool
        @Binding var hasDetectionFailed: Bool

        var body: some View {
            Button {
                performAction()
            } label: {
                Text(buttonLabel)
                    .font(.body)
                    .bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 25)
                    .padding(.vertical, 20)
                    .background(.blue)
                    .clipShape(.capsule)
            }
        }

        private var buttonLabel: String {
            if case .ready = session.state {
                LocalizedString.continue
            } else if !isObjectFlipped {
                LocalizedString.startCapture
            } else {
                LocalizedString.continue
            }
        }

        private func performAction() {
            if case .ready = session.state {
                Logger.scanner3D.debug("here")
                hasDetectionFailed = !session.startDetecting()
            } else if case .detecting = session.state {
                session.startCapturing()
            }
        }
    }
}

#Preview {
    @Previewable @State var hasDetectionFailed = false

    CaptureOverlayView.CaptureButton(
        session: ObjectCaptureSession(),
        isObjectFlipped: false,
        hasDetectionFailed: $hasDetectionFailed
    )
}

#endif
