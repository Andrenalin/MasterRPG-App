/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI
import os

extension CaptureOverlayView {
    struct CaptureHelpButton: View {
        @Binding var showInfo: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button {
                Logger.scanner3D.log("\(LocalizedString.help) button clicked!")
                withAnimation(reduceMotion ? nil : .default) {
                    showInfo = true
                }
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22)

                    Text(LocalizedString.help)
                        .font(.footnote)
                        .opacity(0.7)
                        .bold()
                }
                .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    @Previewable @State var showInfo = false

    CaptureOverlayView.CaptureHelpButton(showInfo: $showInfo)
        .padding()
        .background(.black)
}

#endif
