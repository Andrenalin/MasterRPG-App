/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import RealityKit
import SwiftUI
import os

extension CaptureOverlayView {
    struct CaptureCancelButton: View {
        @Environment(AppDataModel.self) private var appModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            Button {
                Logger.scanner3D.log("\(LocalizedString.cancel) button clicked!")
                appModel.cancelAndDismiss()
                dismiss()
            } label: {
                Text(LocalizedString.cancel)
                    .modifier(VisualEffectRoundedCorner())
            }
        }
    }
}

#Preview {
    CaptureOverlayView.CaptureCancelButton()
        .environment(AppDataModel.instance)
}

#endif
