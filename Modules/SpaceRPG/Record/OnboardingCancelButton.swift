/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI
import os

struct OnboardingCancelButton: View {
    @Environment(AppDataModel.self) private var appModel
    let buttonLabel: String

    var body: some View {
        Button {
            Logger.scanner3D.log("Cancel button clicked!")
            appModel.setPreviewModelState(shown: false)
        } label: {
            Text(buttonLabel)
                .font(.headline)
                .bold()
                .padding(30)
                .foregroundStyle(.blue)
        }
    }
}

#Preview {
    OnboardingCancelButton(buttonLabel: "Cancel")
        .environment(AppDataModel.instance)
}

#endif
