/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Top-level SwiftUI container view for the entire app.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import RealityKit
import SwiftUI
import os

extension Logger {
    static let scanner3D = Logger(subsystem: subsystem, category: "Scanner3D")
}

#Preview {
    Scanner3DRootView(itemId: UUID()) { _ in }
}

struct Scanner3DRootView: View {
    let itemId: UUID
    /// Called once the user finishes reviewing the reconstructed model, with the produced
    /// USDZ file's URL, so the caller can attach it to the item the scanner was opened from.
    let onCaptureFinished: @MainActor @Sendable (URL) async -> Void

    @State private var appModel: AppDataModel = AppDataModel.instance

    @State private var showReconstructionView: Bool = false
    @State private var showErrorAlert: Bool = false
    private var showProgressView: Bool {
        appModel.state == .completed || appModel.state == .restart || appModel.state == .ready
    }

    var body: some View {
        VStack {
            if appModel.state == .capturing {
                if let session = appModel.objectCaptureSession {
                    CapturePrimaryView(session: session)
                }
            } else if showProgressView {
                CircularProgressView()
            }
        }
        .onChange(of: appModel.state) { _, newState in
            if newState == .failed {
                showErrorAlert = true
                showReconstructionView = false
            } else {
                showErrorAlert = false
                showReconstructionView = newState == .reconstructing || newState == .viewing
            }
        }
        .sheet(isPresented: $showReconstructionView) {
            ManagedPresentationView {
                if let folderManager = appModel.scanFolderManager {
                    ReconstructionPrimaryView(
                        outputFile: folderManager.modelsFolder.appending(path: "model-mobile.usdz"),
                        onCaptureFinished: onCaptureFinished
                    )
                }
            }
        }
        .alert(
            Text(
                "Failed: \(appModel.error.map { String(describing: $0) } ?? "")",
                bundle: .module
            ),
            isPresented: $showErrorAlert,
            actions: {
                Button { appModel.state = .restart; Logger.scanner3D.log("Calling restart...") } label: { Text("OK", bundle: .module) }
            },
            message: {}
        )
        .environment(appModel)
    }
}

#endif
