/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import RealityKit
import SwiftUI

extension CaptureOverlayView {
    struct ResetBoundingBoxButton: View {
        var session: ObjectCaptureSession

        var body: some View {
            Button {
                session.resetDetection()
            } label: {
                VStack(spacing: 6) {
                    Image("ResetBbox", bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30)

                    Text(LocalizedString.resetBox)
                        .font(.footnote)
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .bold()
            }
        }
    }
}

#Preview {
    CaptureOverlayView.ResetBoundingBoxButton(session: ObjectCaptureSession())
        .padding()
        .background(.black)
}

#endif
