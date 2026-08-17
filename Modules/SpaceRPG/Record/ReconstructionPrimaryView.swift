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
    /// Called once the user finishes reviewing the reconstructed model, with the produced
    /// USDZ file's URL, so the caller can attach it to the item the scanner was opened from.
    let onCaptureFinished: @MainActor @Sendable (URL) async -> Void

    @State private var completed = false
    @State private var cancelled = false

    var body: some View {
        if completed && !cancelled {
            ModelView(modelFile: outputFile) { [weak appModel, outputFile, onCaptureFinished] in
                Task {
                    await onCaptureFinished(outputFile)
                    appModel?.endCapture()
                }
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
    ReconstructionPrimaryView(
        outputFile: PreviewAssetFixture.url(.space) ?? URL(filePath: "/dev/null"),
        onCaptureFinished: { _ in }
    )
        .environment(AppDataModel.instance)
}

#endif
