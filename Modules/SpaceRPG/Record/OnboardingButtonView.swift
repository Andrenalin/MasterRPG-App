/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The buttons on the review screen.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import RealityKit
import SwiftUI
import os

/// View that creates the buttons on the review screen depending on
/// `currentState` in `onboardingStateMachine`.
struct OnboardingButtonView: View {
    @Environment(AppDataModel.self) private var appModel
    var session: ObjectCaptureSession
    let onboardingStateMachine: OnboardingStateMachine
    @State private var userHasIndicatedObjectCannotBeFlipped: Bool? = nil
    @State private var userHasIndicatedFlipObjectAnyway: Bool? = nil

    var body: some View {
        VStack {
            HStack {
                OnboardingCancelButton(buttonLabel: LocalizedString.cancel)
                Spacer()
            }

            Spacer()

            VStack(spacing: 0) {
                let currentStateInputs = onboardingStateMachine.currentStateInputs()
                if currentStateInputs.contains(where: { $0 == .continue(isFlippable: false) || $0 == .continue(isFlippable: true) }) {
                    OnboardingCreateButton(buttonLabel: LocalizedString.continue,
                                 buttonLabelColor: .white,
                                 shouldApplyBackground: true,
                                 action: { transition(with: .continue(isFlippable: appModel.isObjectFlippable)) }
                    )
                }
                if currentStateInputs.contains(where: { $0 == .flipObjectAnyway }) {
                    OnboardingCreateButton(buttonLabel: LocalizedString.flipAnyway,
                                 buttonLabelColor: .blue,
                                 action: {
                        userHasIndicatedFlipObjectAnyway = true
                        transition(with: .flipObjectAnyway)
                    })
                }
                if currentStateInputs.contains(where: { $0 == .skip(isFlippable: false) || $0 == .skip(isFlippable: true) }) {
                    OnboardingCreateButton(buttonLabel: LocalizedString.skip,
                                 buttonLabelColor: .blue,
                                 action: {
                        transition(with: .skip(isFlippable: appModel.isObjectFlippable))
                    })
                }
                if currentStateInputs.contains(where: { $0 == .finish }) {
                    OnboardingCreateButton(buttonLabel: LocalizedString.finish,
                                 buttonLabelColor: onboardingStateMachine.currentState == .thirdSegmentComplete ? .white : .blue,
                                 shouldApplyBackground: onboardingStateMachine.currentState == .thirdSegmentComplete,
                                 showBusyIndicator: session.state == .finishing,
                                 action: { [weak session] in session?.finish() })
                }
                if currentStateInputs.contains(where: { $0 == .objectCannotBeFlipped }) {
                    OnboardingCreateButton(buttonLabel: LocalizedString.cannotFlipYourObject,
                                 buttonLabelColor: .blue,
                                 action: {
                        userHasIndicatedObjectCannotBeFlipped = true
                        transition(with: .objectCannotBeFlipped)
                    })
                }
                if onboardingStateMachine.currentState == OnboardingState.tooFewImages ||
                    onboardingStateMachine.currentState == .secondSegmentComplete  ||
                    onboardingStateMachine.currentState == .thirdSegmentComplete {
                    OnboardingCreateButton(buttonLabel: "", action: {})
                }
            }
            .padding(.bottom)
        }
    }

    private func reloadData() {
        switch onboardingStateMachine.currentState {
            case .firstSegment, .dismiss:
                appModel.setPreviewModelState(shown: false)
            case .secondSegment, .thirdSegment, .additionalOrbitOnCurrentSegment:
                beginNewOrbitOrSection()
            default:
                break
        }
    }

    private func beginNewOrbitOrSection() {
        if let userHasIndicatedObjectCannotBeFlipped = userHasIndicatedObjectCannotBeFlipped {
            appModel.hasIndicatedObjectCannotBeFlipped = userHasIndicatedObjectCannotBeFlipped
        }

        if let userHasIndicatedFlipObjectAnyway = userHasIndicatedFlipObjectAnyway {
            appModel.hasIndicatedFlipObjectAnyway = userHasIndicatedFlipObjectAnyway
        }

        if !appModel.isObjectFlippable && !appModel.hasIndicatedFlipObjectAnyway {
            session.beginNewScanPass()
        } else {
            session.beginNewScanPassAfterFlip()
            appModel.isObjectFlipped = true
        }
        appModel.setPreviewModelState(shown: false)
        appModel.orbitState = .initial
        appModel.orbit = appModel.orbit.next()
    }

    private func transition(with input: OnboardingUserInput) {
        guard onboardingStateMachine.enter(input) else {
            Logger.scanner3D.log("Could not move to new state in User Guide state machine")
            return
        }
        reloadData()
    }
}

#Preview("Onboarding Buttons") {
    OnboardingButtonView(session: ObjectCaptureSession(), onboardingStateMachine: OnboardingStateMachine(.firstSegment))
        .environment(AppDataModel.instance)
}

#endif
