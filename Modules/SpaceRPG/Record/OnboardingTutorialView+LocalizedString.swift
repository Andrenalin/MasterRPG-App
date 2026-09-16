/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The localized strings the onboarding tutorial view uses.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation

extension OnboardingTutorialView {
    struct LocalizedString {
        static let tooFewImagesTitle = String(
            localized: "Keep moving around your object. (Review, Object Capture)",
            defaultValue: "Keep moving around your object.",
            bundle: .module,
            comment: "Feedback title for when user has less than the minimum images required."
        )

        static let tooFewImagesDetailText = String(
            localized: "You need at least \(CaptureConstants.minNumImages) images of your object to create a model.",
            bundle: .module,
            comment: "Feedback for when the user has fewer than the minimum required images."
        )

        static let firstSegmentNeedsWorkTitle = String(
            localized: "Keep going to complete the first segment. (Review, Object Capture)",
            defaultValue: "Keep going to complete the first segment.",
            bundle: .module,
            comment: "Feedback title for when user still has work to do to complete the first segment."
        )

        static let firstSegmentNeedsWorkDetailText = String(
            localized: """
                For best quality, capture three segments.
                Tap Skip if you can't make it all the way around, but your final model may have missing areas. (Review, Object Capture, 1st Segment)
                """,
            defaultValue: """
                For best quality, capture three segments.
                Tap Skip if you can't make it all the way around, but your final model may have missing areas.
                """,
            bundle: .module,
            comment: "Feedback for when user still has work to do to complete the first segment."
        )

        static let firstSegmentCompleteTitle = String(
            localized: "First segment complete. (Review, Object Capture)",
            defaultValue: "First segment complete.",
            bundle: .module,
            comment: "Feedback title for when user has finished capturing first segment."
        )

        static let firstSegmentCompleteDetailText = String(
            localized: "For best quality, capture three segments. (Review, Object Capture, 1st Segment)",
            defaultValue: "For best quality, caputure three segments.",
            bundle: .module,
            comment: "Feedback for when user has finished capturing first segment."
        )

        static let flipObjectTitle = String(
            localized: "Flip object on its side and capture again. (Review, Object Capture)",
            defaultValue: "Flip object on its side and capture again.",
            bundle: .module,
            comment: "Feedback title for when user should flip the object and capture again."
        )

        static let flipObjectDetailText = String(
            localized: "Make sure that areas you captured previously can still be seen. (Review, Object Capture)",
            defaultValue: "Make sure that areas you captured previously can still be seen. Avoid flipping your object if it changes the shape.",
            bundle: .module,
            comment: "Feedback for when user should flip the object and capture again"
        )

        static let flippingObjectNotRecommendedTitle = String(
            localized: "Flipping this object is not recommended. (Review, Object Capture)",
            defaultValue: "Flipping this object is not recommended.",
            bundle: .module,
            comment: "Feedback title that this object is likely to fail if flipped."
        )

        static let flippingObjectNotRecommendedDetailText = String(
            localized: """
                Your object may have single color surfaces or be too reflective to add more segments.
                Tap Continue to capture more detail without flipping, or Flip Object Anyway. (Review, Object Capture)
                """,
            defaultValue: """
                Your object may have single color surfaces or be too reflective to add more segments.
                Tap Continue to capture more detail without flipping, or Flip Object Anyway.
                """,
            bundle: .module,
            comment: "Feedback that this object is likely to fail if flipped."
        )

        static let captureFromLowerAngleTitle = String(
            localized: "Capture your object again from a lower angle. (Review, Object Capture)",
            defaultValue: "Capture your object again from a lower angle.",
            bundle: .module,
            comment: "Feedback title for when user should capture again from a lower angle given flipping isn't recommended."
        )

        static let captureFromLowerAngleDetailText = String(
            localized: "Move down to be level with the base of your object and capture again. (Review, Object Capture)",
            defaultValue: "Move down to be level with the base of your object and capture again.",
            bundle: .module,
            comment: "Feedback for when user should capture again from a lower angle given flipping isn't recommended."
        )

        static let secondSegmentNeedsWorkTitle = String(
            localized: "Keep going to complete the second segment. (Review, Object Capture)",
            defaultValue: "Keep going to complete the second segment.",
            bundle: .module,
            comment: "Feedback title for when user has not finished capturing second segment."
        )

        static let secondSegmentNeedsWorkDetailText = String(
            localized: """
                For best quality, capture three segments.
                Tap Skip if you can't make it all the way around but your final model may have missing areas. (Review, Object Capture, 2nd Segment)
                """,
            defaultValue: """
                For best quality, capture three segments.
                Tap Skip if you can't make it all the way around but your final model may have missing areas.
                """,
            bundle: .module,
            comment: "Feedback title for when user has not finished capturing second segment."
        )

        static let secondSegmentCompleteTitle = String(
            localized: "Second segment complete. (Review, Object Capture)",
            defaultValue: "Second segment complete.",
            bundle: .module,
            comment: "Feedback title for when user has finished capturing second segment."
        )

        static let secondSegmentCompleteDetailText = String(
            localized: "For best quality, capture three segments. (Review, Object Capture, 2nd segment)",
            defaultValue: "For best quality, capture three segments.",
            bundle: .module,
            comment: "Feedback title for when user has finished capturing second segment."
        )

        static let flipObjectASecondTimeTitle = String(
            localized: "Flip object on the opposite side and capture again. (Review, Object Capture)",
            defaultValue: "Flip object on the opposite side and capture again",
            bundle: .module,
            comment: "Feedback title for when user has not flipped object on the opposite side."
        )

        static let flipObjectASecondTimeDetailText = String(
            localized: "Make sure that areas you captured previously can still be seen. (Review, Object Capture)",
            defaultValue: "Make sure that areas you captured previously can still be seen. Avoid flipping your object if it changes the shape.",
            bundle: .module,
            comment: "Feedback for when user has not flipped object on the opposite side."
        )

        static let captureFromHigherAngleTitle = String(
            localized: "Capture your object again from a higher angle. (Review, Object Capture)",
            defaultValue: "Capture your object again from a higher angle.",
            bundle: .module,
            comment: "Feedback title for when user should capture again from a higher angle given flipping isn't recommended."
        )

        static let captureFromHigherAngleDetailText = String(
            localized: "Move above your object and make sure that areas you captured previously can still be seen. (Review, Object Capture)",
            defaultValue: "Move above your object and make sure that areas you captured previously can still be seen.",
            bundle: .module,
            comment: "Feedback for when user should capture again from above given flipping isn't recommended."
        )

        static let thirdSegmentNeedsWorkTitle = String(
            localized: "Keep going to complete the final segment. (Review, Object Capture)",
            defaultValue: "Keep going to complete the final segment.",
            bundle: .module,
            comment: "Feedback title for when user still has work to do to complete the final segment."
        )

        static let thirdSegmentNeedsWorkDetailText = String(
            localized: "For best quality, capture three segments. When you're done, tap Finish to complete your object. (Review, Object Capture)",
            defaultValue: "For best quality, capture three segments. When you're done, tap Finish to complete your object.",
            bundle: .module,
            comment: "Feedback for when user still has work to do to complete the final segment."
        )

        static let thirdSegmentCompleteTitle = String(
            localized: "All segments complete. (Review, Object Capture)",
            defaultValue: "All segments complete.",
            bundle: .module,
            comment: "Feedback title for when user has finished capturing final segment."
        )

        static let thirdSegmentCompleteDetailText = String(
            localized: "Tap Finish to process your object. (Review, Object Capture)",
            defaultValue: "Tap Finish to process your object.",
            bundle: .module,
            comment: "Feedback for when user has finished capturing final segment."
        )
    }
}

#endif
