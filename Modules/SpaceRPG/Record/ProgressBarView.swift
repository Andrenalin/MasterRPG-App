/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Encapsulated view support for the scanning progress meter.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import SwiftUI
import RealityKit

struct ProgressBarView: View {
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

    private var numOfImages: Int {
        guard let folderManager = appModel.scanFolderManager else { return 0 }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderManager.imagesFolder,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return urls.filter { $0.pathExtension.uppercased() == "HEIC" }.count
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
        static let processing = NSLocalizedString(
            "Processing (Object Capture)",
            bundle: LocString.bundleForLocalizedStrings,
            value: "Processing…",
            comment: "Processing title for object reconstruction."
        )

        static let processingModelDescription = NSLocalizedString(
            "Keep app running while processing. (Object Capture)",
            bundle: LocString.bundleForLocalizedStrings,
            value: "Keep app running while processing.",
            comment: "Description displayed while processing models."
        )

        static let calculating = NSLocalizedString(
            "Calculating… (Estimated time, Object Capture)",
            bundle: LocString.bundleForLocalizedStrings,
            value: "Calculating…",
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
