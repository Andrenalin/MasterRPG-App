/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI
import os

struct OnboardingCreateButton: View {
    let buttonLabel: String
    var buttonLabelColor: Color = .white
    var buttonBackgroundColor: Color = .blue
    var shouldApplyBackground = false
    var showBusyIndicator = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            Logger.scanner3D.log("\(buttonLabel) clicked!")
            action()
        } label: {
            ZStack {
                if showBusyIndicator {
                    HStack {
                        Text(buttonLabel)
                            .hidden()
                        Spacer()
                            .frame(maxWidth: 48)
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(
                                    tint: shouldApplyBackground ? .white : (colorScheme == .light ? .black : .white)
                                )
                            )
                    }
                }
                Text(buttonLabel)
                    .font(.headline)
                    .bold()
                    .foregroundStyle(buttonLabelColor)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
        }
        .if(shouldApplyBackground) { view in
            view.background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(buttonBackgroundColor)
            )
        }
        .padding(.horizontal)
        .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 380 : .infinity)
        .disabled(buttonLabel.isEmpty)
        .accessibilityHidden(buttonLabel.isEmpty)
    }
}

#Preview {
    OnboardingCreateButton(buttonLabel: "Continue", shouldApplyBackground: true, action: {})
}

#endif
