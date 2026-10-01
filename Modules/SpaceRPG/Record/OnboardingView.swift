/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The view that shows the guidance text and tutorials on the review screen.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import RealityKit
import SwiftUI

/// View that shows the guidance text and tutorials on the review screen.
struct OnboardingView: View {
    @Environment(AppDataModel.self) private var appModel
    @State private var stateMachine: OnboardingStateMachine

    init(state: OnboardingState) {
        _stateMachine = State(wrappedValue: OnboardingStateMachine(state))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            if let session = appModel.objectCaptureSession {
                OnboardingTutorialView(session: session, onboardingStateMachine: stateMachine)
                OnboardingButtonView(session: session, onboardingStateMachine: stateMachine)
            }
        }
        .interactiveDismissDisabled(appModel.objectCaptureSession?.userCompletedScanPass ?? false)
        .allowsHitTesting(!isFinishingOrCompleted)
        .accessibilityHidden(isFinishingOrCompleted)
    }

    private var isFinishingOrCompleted: Bool {
        guard let session = appModel.objectCaptureSession else { return true }
        return session.state == .finishing || session.state == .completed
    }
}

#Preview {
    OnboardingView(state: .firstSegment)
        .environment(AppDataModel.instance)
}

#endif
