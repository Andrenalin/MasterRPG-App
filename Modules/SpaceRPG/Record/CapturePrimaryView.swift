/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Top-level view for the object capture session that shows the info panel and other items during the session.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import Foundation
import RealityKit
import SwiftUI

struct CapturePrimaryView: View {
    @Environment(AppDataModel.self) private var appModel
    var session: ObjectCaptureSession

    // Pauses the scanning and shows tutorial pages. This sample passes it as
    // a binding to the two views so buttons can change the state.
    @State private var showInfo: Bool = false
    @State private var showOnboardingView: Bool = false

    var body: some View {
        ZStack {
            ObjectCaptureView(session: session,
                              cameraFeedOverlay: { GradientBackground() })
            .ignoresSafeArea()
            .blur(radius: appModel.showPreviewModel ? 45 : 0)
            .transition(.opacity)
            if shouldShowOverlayView {
                CaptureOverlayView(session: session, showInfo: $showInfo)
            }
        }
        .sheet(isPresented: $showInfo) {
            ManagedPresentationView {
                HelpPageView(showInfo: $showInfo)
                    .padding()
            }
        }
        .sheet(isPresented: $showOnboardingView,
               onDismiss: { [weak appModel] in appModel?.setPreviewModelState(shown: false) },
               content: {[weak appModel] in
            ManagedPresentationView {
                if let appModel = appModel, let onboardingState = appModel.determineCurrentOnboardingState() {
                    OnboardingView(state: onboardingState)
                }
            }
        })
        .task {
            for await userCompletedScanPass in session.userCompletedScanPassUpdates where userCompletedScanPass {
                    appModel.setPreviewModelState(shown: true)
            }
        }
        .onChange(of: appModel.showPreviewModel, {_, showPreviewModel in
            if !showInfo {
                showOnboardingView = showPreviewModel
            }
        })
        .onChange(of: showInfo) {
            appModel.setPreviewModelState(shown: showInfo)
        }
        .onAppear(perform: {
            KeepAwakeModel.shared.acquire(.capture)
        })
        .onDisappear(perform: {
            KeepAwakeModel.shared.release(.capture)
        })
        .id(session.id)
    }

    private var shouldShowOverlayView: Bool {
        // Apple's original `CapturePrimaryView` shows `CaptureOverlayView` unconditionally —
        // `CaptureOverlayView` already adapts its own content to `session.state` internally.
        // Gating the whole overlay on `session.cameraTracking == .normal` (as this used to)
        // has no counterpart there: if tracking never reports exactly `.normal` — even once the
        // system's own ARKit coaching overlay has genuinely dismissed and capture could proceed —
        // the entire capture UI (bounding-box guidance, Continue/Capture buttons) never mounts,
        // leaving a bare camera feed with nothing to interact with.
        !showInfo && !appModel.showPreviewModel && !session.isPaused
    }
}

#Preview {
    CapturePrimaryView(session: ObjectCaptureSession())
        .environment(AppDataModel.instance)
}

#endif
