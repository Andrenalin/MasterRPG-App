/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The guidance view that shows the video tutorial or the point cloud on the review screen.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import RealityKit
import SwiftUI

/// The view that either shows the point cloud or plays the guidance tutorials on the review screens.
/// This depends on `currentState` in `onboardingStateMachine`.
struct OnboardingTutorialView: View {
    @Environment(AppDataModel.self) private var appModel
    var session: ObjectCaptureSession
    let onboardingStateMachine: OnboardingStateMachine

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tutorialUrl: URL?

    var body: some View {
        VStack {
            ZStack {
                if shouldShowTutorialInReview, let url = tutorialUrl {
                    TutorialVideoView(url: url, isInReviewSheet: true)
                        .padding(30)
                } else {
                    ObjectCapturePointCloudView(session: session)
                        .padding(30)
                }

                VStack {
                    Spacer()
                    HStack {
                        ForEach(AppDataModel.Orbit.allCases) { orbit in
                            if let orbitImageName = getOrbitImageName(orbit: orbit) {
                                Text(Image(systemName: orbitImageName))
                                    .font(.title2)
                                    .foregroundStyle(.gray)
                                    .accessibilityLabel(
                                        Text("Scan pass \(orbit.rawValue + 1)", bundle: .module)
                                    )
                                    .accessibilityValue(
                                        orbit < appModel.orbit || session.userCompletedScanPass
                                            ? Text("Complete", bundle: .module)
                                            : Text("Pending", bundle: .module)
                                    )
                            }
                        }
                    }
                    .padding(.bottom)
                }
            }
            .frame(maxHeight: .infinity)

            VStack {
                Text(title)
                    .font(.largeTitle)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                    .frame(maxWidth: .infinity)

                Text(detailText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
            .frame(maxHeight: .infinity)
            .padding(.leading, horizontalSizeClass == .regular ? 50 : 30)
            .padding(.trailing, horizontalSizeClass == .regular ? 50 : 30)

        }
        .onChange(of: onboardingStateMachine.currentState, initial: true) { _, newState in
            tutorialUrl = Self.tutorialVideoUrl(for: newState, isRegularWidth: horizontalSizeClass == .regular)
        }
    }

    private var shouldShowTutorialInReview: Bool {
        switch onboardingStateMachine.currentState {
            case .flipObject, .flipObjectASecondTime, .captureFromLowerAngle, .captureFromHigherAngle:
                return true
            default:
                return false
        }
    }

    private static let onboardingStateToTutorialNameMapOnIphone: [OnboardingState: String] = [
        .flipObject: "ScanPasses-iPhone-FixedHeight-2",
        .flipObjectASecondTime: "ScanPasses-iPhone-FixedHeight-3",
        .captureFromLowerAngle: "ScanPasses-iPhone-FixedHeight-unflippable-low",
        .captureFromHigherAngle: "ScanPasses-iPhone-FixedHeight-unflippable-high"
    ]

    private static let onboardingStateToTutorialNameMapOnIpad: [OnboardingState: String] = [
        .flipObject: "ScanPasses-iPad-FixedHeight-2",
        .flipObjectASecondTime: "ScanPasses-iPad-FixedHeight-3",
        .captureFromLowerAngle: "ScanPasses-iPad-FixedHeight-unflippable-low",
        .captureFromHigherAngle: "ScanPasses-iPad-FixedHeight-unflippable-high"
    ]

    // Resolved once per `currentState` change (see the `.onChange` in `body`) instead of on
    // every body evaluation. See CODE_AUDIT_Space §7.2.
    private static func tutorialVideoUrl(for state: OnboardingState, isRegularWidth: Bool) -> URL? {
        let videoName: String
        if isRegularWidth {
            videoName = onboardingStateToTutorialNameMapOnIpad[state] ?? "ScanPasses-iPad-FixedHeight-1"
        } else {
            videoName = onboardingStateToTutorialNameMapOnIphone[state] ?? "ScanPasses-iPhone-FixedHeight-1"
        }
        return Bundle.module.url(forResource: videoName, withExtension: "mp4")
    }

    private func getOrbitImageName(orbit: AppDataModel.Orbit) -> String? {
        guard let session = appModel.objectCaptureSession else { return nil }
        let orbitCompleted = session.userCompletedScanPass
        let orbitCompleteImage = orbit <= appModel.orbit ? orbit.imageSelected : orbit.image
        let orbitNotCompleteImage = orbit < appModel.orbit ? orbit.imageSelected : orbit.image
        return orbitCompleted ? orbitCompleteImage : orbitNotCompleteImage
    }

    private static let onboardingStateToTitleMap: [OnboardingState: String] = [
        .tooFewImages: LocalizedString.tooFewImagesTitle,
        .firstSegmentNeedsWork: LocalizedString.firstSegmentNeedsWorkTitle,
        .firstSegmentComplete: LocalizedString.firstSegmentCompleteTitle,
        .secondSegmentNeedsWork: LocalizedString.secondSegmentNeedsWorkTitle,
        .secondSegmentComplete: LocalizedString.secondSegmentCompleteTitle,
        .thirdSegmentNeedsWork: LocalizedString.thirdSegmentNeedsWorkTitle,
        .thirdSegmentComplete: LocalizedString.thirdSegmentCompleteTitle,
        .flipObject: LocalizedString.flipObjectTitle,
        .flipObjectASecondTime: LocalizedString.flipObjectASecondTimeTitle,
        .flippingObjectNotRecommended: LocalizedString.flippingObjectNotRecommendedTitle,
        .captureFromLowerAngle: LocalizedString.captureFromLowerAngleTitle,
        .captureFromHigherAngle: LocalizedString.captureFromHigherAngleTitle
    ]

    private var title: String {
        Self.onboardingStateToTitleMap[onboardingStateMachine.currentState] ?? ""
    }

    private static let onboardingStateToDetailTextMap: [OnboardingState: String] = [
        .tooFewImages: LocalizedString.tooFewImagesDetailText,
        .firstSegmentNeedsWork: LocalizedString.firstSegmentNeedsWorkDetailText,
        .firstSegmentComplete: LocalizedString.firstSegmentCompleteDetailText,
        .secondSegmentNeedsWork: LocalizedString.secondSegmentNeedsWorkDetailText,
        .secondSegmentComplete: LocalizedString.secondSegmentCompleteDetailText,
        .thirdSegmentNeedsWork: LocalizedString.thirdSegmentNeedsWorkDetailText,
        .thirdSegmentComplete: LocalizedString.thirdSegmentCompleteDetailText,
        .flipObject: LocalizedString.flipObjectDetailText,
        .flipObjectASecondTime: LocalizedString.flipObjectASecondTimeDetailText,
        .flippingObjectNotRecommended: LocalizedString.flippingObjectNotRecommendedDetailText,
        .captureFromLowerAngle: LocalizedString.captureFromLowerAngleDetailText,
        .captureFromHigherAngle: LocalizedString.captureFromHigherAngleDetailText
    ]

    private var detailText: String {
        Self.onboardingStateToDetailTextMap[onboardingStateMachine.currentState] ?? ""
    }
}

#Preview {
    OnboardingTutorialView(
        session: ObjectCaptureSession(),
        onboardingStateMachine: OnboardingStateMachine(.firstSegment)
    )
    .environment(AppDataModel.instance)
}

#endif
