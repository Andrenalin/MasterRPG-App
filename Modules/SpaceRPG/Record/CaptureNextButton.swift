/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI
import os

extension CaptureOverlayView {
    struct CaptureNextButton: View {
        @Environment(AppDataModel.self) private var appModel

        var body: some View {
            Button {
                Logger.scanner3D.log("\(LocalizedString.next) button clicked!")
                appModel.setPreviewModelState(shown: true)
            } label: {
                Text(LocalizedString.next)
                    .modifier(VisualEffectRoundedCorner())
            }
        }
    }
}

#Preview {
    CaptureOverlayView.CaptureNextButton()
        .environment(AppDataModel.instance)
}

#endif
