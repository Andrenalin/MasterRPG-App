/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A full-screen overlay UI with buttons that control the capture.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import RealityKit
import SwiftUI

struct CaptureOverlayView: View {
    @Environment(AppDataModel.self) private var appModel
    var session: ObjectCaptureSession

    // This sample passes the binding from parent to allow this view
    // to control whether certain panels are shown in `CapturePrimaryView`.
    @Binding var showInfo: Bool

    @State private var hasDetectionFailed = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                CaptureCancelButton()
                    .opacity(!shouldShowTutorial ? 1 : 0)
                    .disabled(shouldDisableCancelButton)
                    .accessibilityHidden(shouldShowTutorial)
                Spacer()
                CaptureNextButton()
                    .opacity(shouldShowNextButton ? 1 : 0)
                    .disabled(!shouldShowNextButton)
                    .accessibilityHidden(!shouldShowNextButton)
            }
            .foregroundStyle(.white)

            Spacer()

            if shouldShowTutorial, let url = Bundle.main.url(
                forResource: appModel.orbit.feedbackVideoName(
                    for: UIDevice.current.userInterfaceIdiom,
                    isObjectFlippable: appModel.isObjectFlippable),
                withExtension: "mp4") {
                TutorialVideoView(url: url, isInReviewSheet: false)
                    .frame(maxHeight: horizontalSizeClass == .regular ? 350 : 280)

                Spacer()
            } else if !capturingStarted {
                BoundingBoxGuidanceView(session: session, hasDetectionFailed: hasDetectionFailed)
            }

            HStack(alignment: .bottom, spacing: 0) {
                HStack(spacing: 0) {
                    if case .capturing = session.state {
                        NumOfImagesButton(session: session)
                            .rotationEffect(rotationAngle)
                            .transition(.opacity)
                    } else if case .detecting = session.state {
                        ResetBoundingBoxButton(session: session)
                            .transition(.opacity)
                    } else if case .ready = session.state {
                        CaptureFilesButton()
                            .transition(.opacity)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                if !capturingStarted {
                    CaptureButton(session: session, isObjectFlipped: appModel.isObjectFlipped, hasDetectionFailed: $hasDetectionFailed)
                        .layoutPriority(1)
                }

                HStack {
                    Spacer()

                    if !capturingStarted {
                        CaptureHelpButton(showInfo: $showInfo)
                            .transition(.opacity)
                    } else if case .capturing = session.state {
                        ManualShotButton(session: session)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .opacity(shouldShowTutorial ? 0 : 1) // Keeps tutorial view centered.
            .accessibilityHidden(shouldShowTutorial)
        }
        .padding()
        .padding(.horizontal, 15)
        .background(shouldShowTutorial ? Color.black.opacity(0.5) : .clear)
        .allowsHitTesting(!shouldShowTutorial)
        .animation(reduceMotion ? nil : .default, value: shouldShowTutorial)
        .background {
            if !shouldShowTutorial && appModel.messageList.activeMessage != nil {
                VStack {
                    Rectangle()
                        .frame(height: 130)
                        .hidden()

                    FeedbackView(messageList: appModel.messageList)
                        .layoutPriority(1)
                }
                .rotationEffect(rotationAngle)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named:
                    UIDevice.orientationDidChangeNotification).map({ $0.name }) {
                withAnimation(reduceMotion ? nil : .default) {
                    deviceOrientation = UIDevice.current.orientation
                }
            }
        }
    }

    private var capturingStarted: Bool {
        switch session.state {
            case .initializing, .ready, .detecting:
                return false
            default:
                return true
        }
    }

    private var shouldShowTutorial: Bool {
        if appModel.orbitState == .initial,
           case .capturing = session.state,
           appModel.orbit == .orbit1 {
            return true
        }
        return false
    }

    private var shouldShowNextButton: Bool {
        capturingStarted && !shouldShowTutorial
    }

    private var shouldDisableCancelButton: Bool {
        shouldShowTutorial || session.state == .ready || session.state == .initializing
    }

    private var rotationAngle: Angle {
        switch deviceOrientation {
            case .landscapeLeft:
                return Angle(degrees: 90)
            case .landscapeRight:
                return Angle(degrees: -90)
            case .portraitUpsideDown:
                return Angle(degrees: 180)
            default:
                return Angle(degrees: 0)
        }
    }
}

#Preview {
    @Previewable @State var showInfo = false
    CaptureOverlayView(session: ObjectCaptureSession(), showInfo: $showInfo)
        .environment(AppDataModel.instance)
}

#endif
