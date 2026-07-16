/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
View to show during the reconstruction phase until the session receives a model output.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import SwiftUI

struct ReconstructionPrimaryView: View {
    @Environment(AppDataModel.self) private var appModel
    let outputFile: URL

    @State private var completed = false
    @State private var cancelled = false

    var body: some View {
        if completed && !cancelled {
            ModelView(modelFile: outputFile) { [weak appModel] in
                appModel?.endCapture()
            }
        } else {
            ReconstructionProgressView(
                outputFile: outputFile,
                completed: $completed,
                cancelled: $cancelled
            )
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .interactiveDismissDisabled()
        }
    }
}

#Preview("Reconstruction") {
    ReconstructionPrimaryView(outputFile: URL(fileURLWithPath: "/dev/null"))
        .environment(AppDataModel.instance)
}

#endif
