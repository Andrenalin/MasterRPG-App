/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import Foundation
@preconcurrency import RealityKit
import SwiftUI
import os

struct ReconstructionProgressView: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.outputFile == rhs.outputFile
    }

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
                        Text(verbatim: LocalizedString.cancel)
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
            .equatable()
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
            guard appModel.state == .reconstructing else {
                Logger.scanner3D.error("ReconstructionProgressView's task ran outside .reconstructing state; surfacing an error instead of crashing.")
                gotError = true
                return
            }
            guard let session = appModel.photogrammetrySession else {
                Logger.scanner3D.error("Missing photogrammetry session while reconstructing")
                gotError = true
                return
            }

            var outputs = UntilProcessingCompleteFilter(input: session.outputs)
            do {
                try session.process(requests: [.modelFile(url: outputFile)])

                while let output = try await outputs.next() {
                    handle(output)
                }
            } catch {
                Logger.scanner3D.error("Processing the session failed: \(String(describing: error))")
                if !isCancelling {
                    gotError = true
                    self.error = error
                }
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
        static let cancel = String(
            localized: "Cancel (Object Reconstruction)",
            defaultValue: "Cancel",
            bundle: .module,
            comment: "Button title to cancel reconstruction"
        )
    }
}

extension PhotogrammetrySession.Output.ProcessingStage {
    var processingStageString: String? {
        switch self {
        case .preProcessing:
            String(
                localized: "Pre-Processing (Reconstruction)",
                defaultValue: "Pre-Processing…",
                bundle: .module,
                comment: "Feedback message during the object reconstruction phase."
            )
        case .imageAlignment:
            String(
                localized: "Aligning Images (Reconstruction)",
                defaultValue: "Aligning Images…",
                bundle: .module,
                comment: "Feedback message during the object reconstruction phase."
            )
        case .pointCloudGeneration:
            String(
                localized: "Generating Point Cloud (Reconstruction)",
                defaultValue: "Generating Point Cloud…",
                bundle: .module,
                comment: "Feedback message during the object reconstruction phase."
            )
        case .meshGeneration:
            String(
                localized: "Generating Mesh (Reconstruction)",
                defaultValue: "Generating Mesh…",
                bundle: .module,
                comment: "Feedback message during the object reconstruction phase."
            )
        case .textureMapping:
            String(
                localized: "Mapping Texture (Reconstruction)",
                defaultValue: "Mapping Texture…",
                bundle: .module,
                comment: "Feedback message during the object reconstruction phase."
            )
        case .optimization:
            String(
                localized: "Optimizing (Reconstruction)",
                defaultValue: "Optimizing…",
                bundle: .module,
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
        outputFile: PreviewAssetFixture.url(.space) ?? URL(filePath: "/dev/null"),
        completed: $completed,
        cancelled: $cancelled
    )
    .environment(AppDataModel.instance)
}

#endif
