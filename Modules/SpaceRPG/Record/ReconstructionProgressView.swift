/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import Foundation
@preconcurrency import RealityKit
import SwiftUI
import os

struct ReconstructionProgressView: View {
    @Environment(AppDataModel.self) private var appModel
    let outputFile: URL
    @Binding var completed: Bool
    @Binding var cancelled: Bool

    @State private var progress: Float = 0
    @State private var estimatedRemainingTime: TimeInterval?
    @State private var processingStageDescription: String?
    @State private var pointCloud: PhotogrammetrySession.PointCloud?
    @State private var gotError = false
    @State private var error: Error?
    @State private var isCancelling = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            if isReconstructing {
                HStack {
                    Button {
                        Logger.scanner3D.log("Cancelling...")
                        isCancelling = true
                        appModel.photogrammetrySession?.cancel()
                    } label: {
                        Text(LocalizedString.cancel)
                            .font(.headline)
                            .bold()
                            .padding(30)
                            .foregroundStyle(.blue)
                    }
                    .padding(.trailing)

                    Spacer()
                }
            }

            Spacer()

            ReconstructionTitleView()

            Spacer()

            ProgressBarView(
                progress: progress,
                estimatedRemainingTime: estimatedRemainingTime,
                processingStageDescription: processingStageDescription
            )
            .padding(contentPadding)

            Spacer()
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
        .alert(
            Text(
                "Failed: \(error.map { String(describing: $0) } ?? "")",
                bundle: .module
            ),
            isPresented: $gotError
        ) {
            Button {
                Logger.scanner3D.log("Calling restart...")
                appModel.state = .restart
            } label: {
                Text("OK", bundle: .module)
            }
        }
        .task {
            precondition(appModel.state == .reconstructing)
            guard let session = appModel.photogrammetrySession else {
                Logger.scanner3D.error("Missing photogrammetry session while reconstructing")
                return
            }

            let outputs = UntilProcessingCompleteFilter(input: session.outputs)
            do {
                try session.process(requests: [.modelFile(url: outputFile)])
            } catch {
                Logger.scanner3D.error("Processing the session failed: \(String(describing: error))")
            }

            for await output in outputs {
                handle(output)
            }
        }
    }

    private var contentPadding: CGFloat {
        horizontalSizeClass == .regular ? 60 : 24
    }

    private var isReconstructing: Bool {
        !completed && !gotError && !cancelled
    }

    private func handle(_ output: PhotogrammetrySession.Output) {
        switch output {
        case .inputComplete:
            break
        case .requestProgress(let request, fractionComplete: let fractionComplete):
            if case .modelFile = request {
                progress = Float(fractionComplete)
            }
        case .requestProgressInfo(let request, let progressInfo):
            if case .modelFile = request {
                estimatedRemainingTime = progressInfo.estimatedRemainingTime
                processingStageDescription = progressInfo.processingStage?.processingStageString
            }
        case .requestComplete(let request, _):
            switch request {
            case .modelFile(_, _, _):
                Logger.scanner3D.log("RequestComplete: .modelFile")
            case .modelEntity(_, _), .bounds, .poses, .pointCloud:
                break
            @unknown default:
                Logger.scanner3D.warning("Received an output for an unknown request: \(String(describing: request))")
            }
        case .requestError(_, let requestError):
            if !isCancelling {
                gotError = true
                error = requestError
            }
        case .processingComplete:
            if !gotError {
                completed = true
                appModel.state = .viewing
            }
        case .processingCancelled:
            cancelled = true
            appModel.state = .restart
        case .invalidSample(id: _, reason: _), .skippedSample(id: _), .automaticDownsampling:
            break
        case .stitchingIncomplete:
            break
        @unknown default:
            Logger.scanner3D.warning("Received an unknown output: \(String(describing: output))")
        }
    }

    private enum LocalizedString {
        static let cancel = NSLocalizedString(
            "Cancel (Object Reconstruction)",
            bundle: LocString.bundleForLocalizedStrings,
            value: "Cancel",
            comment: "Button title to cancel reconstruction"
        )
    }
}

extension PhotogrammetrySession.Output.ProcessingStage {
    var processingStageString: String? {
        switch self {
        case .preProcessing:
            NSLocalizedString(
                "Pre-Processing (Reconstruction)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Pre-Processing…",
                comment: "Feedback message during the object reconstruction phase."
            )
        case .imageAlignment:
            NSLocalizedString(
                "Aligning Images (Reconstruction)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Aligning Images…",
                comment: "Feedback message during the object reconstruction phase."
            )
        case .pointCloudGeneration:
            NSLocalizedString(
                "Generating Point Cloud (Reconstruction)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Generating Point Cloud…",
                comment: "Feedback message during the object reconstruction phase."
            )
        case .meshGeneration:
            NSLocalizedString(
                "Generating Mesh (Reconstruction)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Generating Mesh…",
                comment: "Feedback message during the object reconstruction phase."
            )
        case .textureMapping:
            NSLocalizedString(
                "Mapping Texture (Reconstruction)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Mapping Texture…",
                comment: "Feedback message during the object reconstruction phase."
            )
        case .optimization:
            NSLocalizedString(
                "Optimizing (Reconstruction)",
                bundle: LocString.bundleForLocalizedStrings,
                value: "Optimizing…",
                comment: "Feedback message during the object reconstruction phase."
            )
        default:
            nil
        }
    }
}

#Preview("Reconstruction Progress") {
    @Previewable @State var completed = false
    @Previewable @State var cancelled = false

    ReconstructionProgressView(
        outputFile: URL(fileURLWithPath: "/dev/null"),
        completed: $completed,
        cancelled: $cancelled
    )
    .environment(AppDataModel.instance)
}

#endif
