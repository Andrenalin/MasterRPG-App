/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Generates human-readable strings for each feedback state.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import RealityKit
import SwiftUI

/// Keeps the UI string conversions all in one place for simplicity
final class FeedbackMessages {
    /// Returns the human readable string to display for the given feedback.
    ///
    /// If there's more than one feedback entry, this method concatenates the entries together with a new line in between them.
    static func getFeedbackString(for feedback: ObjectCaptureSession.Feedback) -> String? {
        switch feedback {

            case .objectTooFar:
                return String(
                    localized: "Move Closer (Object Capture)",
                    defaultValue: "Move Closer",
                    bundle: .module,
                    comment: "Feedback message to move closer for object capture")

            case .objectTooClose:
                return String(
                    localized: "Move Farther Away (Object Capture)",
                    defaultValue: "Move Farther Away",
                    bundle: .module,
                    comment: "Feedback message to move back for object capture")

            case .environmentTooDark, .environmentLowLight:
                return String(
                    localized: "More Light Required (Object Capture)",
                    defaultValue: "More Light Required",
                    bundle: .module,
                    comment: "Feedback message to increase lighting for object capture")

            case .movingTooFast:
                return String(
                    localized: "Move slower (Object Capture)",
                    defaultValue: "Move slower",
                    bundle: .module,
                    comment: "Feedback message to slow down for object capture")

            case .outOfFieldOfView:
                return String(
                    localized: "Aim at your object (Object Capture)",
                    defaultValue: "Aim at your object",
                    bundle: .module,
                    comment: "Feedback message to aim at your object for object capture")

            default:
                return nil
        }
    }
}

#endif
