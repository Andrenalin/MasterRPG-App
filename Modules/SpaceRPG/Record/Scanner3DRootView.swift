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
    Scanner3DRootView(itemId: UUID()) { _ in true }
}

struct Scanner3DRootView: View {
    let itemId: UUID
    /// Called once the user finishes reviewing the reconstructed model, with the produced
    /// USDZ file's URL, so the caller can attach it to the item the scanner was opened from.
    /// Returns whether the file was attached.
    let onCaptureFinished: @MainActor @Sendable (URL) async -> Bool

    @State private var appModel: AppDataModel = AppDataModel.instance
    @Environment(\.dismiss) private var dismiss

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
                    .equatable()
            }
        }
        // Apple's sample never needs this: `ContentView` there *is* the app's only
        // `WindowGroup` root, so `ObjectCaptureView` is proposed the screen's own bounds
        // directly. Here it's several layers deeper — `fullScreenCover` →
        // `ManagedPresentationView` (its own `@LazyState` navigator plumbing) → this
        // `VStack` — and a plain `VStack` only adopts a child's flexible ideal size once
        // that child has one to report; forcing it explicitly removes any chance the
        // first layout pass proposes RealityKit's internal `CAMetalLayer` a zero/ambiguous
        // size before it settles (matching the "CAMetalLayer ignoring invalid
        // setDrawableSize width=0.000000 height=0.000000" log lines).
        //
        // The safe area is not ignored here: only the camera feed runs edge to edge (see
        // `CapturePrimaryView`), so the capture controls stay clear of the status bar and
        // the home indicator.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Reopening after a cancel leaves `appModel` idling at `.ready` with no
            // session — see `AppDataModel.cancelAndDismiss()` — so kick off a fresh one.
            // No-op on first launch / while a session is already running.
            appModel.beginCaptureIfNeeded()
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
        // A finished capture closes the scanner; it used to stay up and start the next capture.
        // See CODE_AUDIT_21 §5.21.
        .onChange(of: appModel.finishedCaptures) {
            dismiss()
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
                "Failed: \(appModel.error.map(\.localizedDescription) ?? "")",
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
