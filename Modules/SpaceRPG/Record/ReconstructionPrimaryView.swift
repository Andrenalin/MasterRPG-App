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
    /// Returns whether the file was attached.
    let onCaptureFinished: @MainActor @Sendable (URL) async -> Bool

    @State private var completed = false
    @State private var cancelled = false

    var body: some View {
        if completed && !cancelled {
            ModelView(modelFile: outputFile) { [weak appModel, outputFile, onCaptureFinished] in
                Task {
                    let attached = await onCaptureFinished(outputFile)
                    appModel?.finishCapture(attached: attached)
                }
            }
        } else {
            ReconstructionProgressView(
                outputFile: outputFile,
                completed: $completed,
                cancelled: $cancelled
            )
            .equatable()
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
        onCaptureFinished: { _ in true }
    )
        .environment(AppDataModel.instance)
}

#endif
