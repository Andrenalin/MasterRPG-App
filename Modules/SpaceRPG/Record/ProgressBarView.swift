/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Encapsulated view support for the scanning progress meter.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import SwiftUI
import RealityKit

struct ProgressBarView: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.progress == rhs.progress
            && lhs.estimatedRemainingTime == rhs.estimatedRemainingTime
            && lhs.processingStageDescription == rhs.processingStageDescription
    }

    @Environment(AppDataModel.self) private var appModel
    // The progress value from 0 to 1 which describes how much coverage is done.
    var progress: Float
    var estimatedRemainingTime: TimeInterval?
    var processingStageDescription: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var formattedEstimatedRemainingTime: String? {
        guard let estimatedRemainingTime = estimatedRemainingTime else { return nil }
        return Duration.seconds(estimatedRemainingTime).formatted(
            .time(pattern: .minuteSecond(padMinuteToLength: 2))
        )
    }

    // Reads the shot count `CaptureFolderManager.loadShots()` already cached on entering
    // reconstruction, instead of hitting the filesystem synchronously on every body
    // evaluation. See CODE_AUDIT_Space §7.1.
    private var numOfImages: Int {
        appModel.scanFolderManager?.shots.count ?? 0
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    Text(processingStageDescription ?? LocalizedString.processing)

                    Spacer()

                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .bold()
                        .monospacedDigit()
                }
                .font(.body)

                ProgressView(value: progress)
                    .accessibilityLabel(Text("Reconstruction progress", bundle: .module))
                    .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            }

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .center) {
                    Image(systemName: "photo")

                    Text(verbatim: numOfImages.formatted())
                        .frame(alignment: .bottom)
                        .hidden()
                        .overlay {
                            Text(verbatim: numOfImages.formatted())
                                .font(.caption)
                                .bold()
                        }
                }
                .font(.subheadline)
                .padding(.trailing, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Captured images", bundle: .module))
                .accessibilityValue(Text(verbatim: numOfImages.formatted()))

                VStack(alignment: .leading) {
                    Text(LocalizedString.processingModelDescription)

                    Text(
                        "Estimated time remaining: \(formattedEstimatedRemainingTime ?? LocalizedString.calculating)",
                        bundle: .module
                    )
                }
                .font(.subheadline)
            }
            .foregroundStyle(.secondary)
        }
    }

    private struct LocalizedString {
        static let processing = String(
            localized: "Processing (Object Capture)",
            defaultValue: "Processing…",
            bundle: .module,
            comment: "Processing title for object reconstruction."
        )

        static let processingModelDescription = String(
            localized: "Keep app running while processing. (Object Capture)",
            defaultValue: "Keep app running while processing.",
            bundle: .module,
            comment: "Description displayed while processing models."
        )

        static let calculating = String(
            localized: "Calculating… (Estimated time, Object Capture)",
            defaultValue: "Calculating…",
            bundle: .module,
            comment: "When estimated processing time isn't available yet."
        )
    }
}

#Preview {
    ProgressBarView(
        progress: 0.65,
        estimatedRemainingTime: 90,
        processingStageDescription: "Creating model"
    )
    .environment(AppDataModel.instance)
    .padding()
}

#endif
