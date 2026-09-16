/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's internal localized string type.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation

extension CaptureOverlayView {
    struct LocalizedString {
        static let startCapture = String(
            localized: "Start Capture (Object Capture)",
            defaultValue: "Start Capture",
            bundle: .module,
            comment: "Title for start capture button on the object capture screen.")

        static let resetBox = String(
            localized: "Reset Box (Object Capture)",
            defaultValue: "Reset Box",
            bundle: .module,
            comment: "Title for resetting bounding box on the object capture screen.")

        static let `continue` = String(
            localized: "Continue (Object Capture, Capture)",
            defaultValue: "Continue",
            bundle: .module,
            comment: "Title for continue button on the object capture screen.")

        static let next = String(
            localized: "Next (Object Capture)",
            defaultValue: "Next",
            bundle: .module,
            comment: "Title for next button on the object capture screen.")

        static let cancel = String(
            localized: "Cancel (Object Capture)",
            defaultValue: "Cancel",
            bundle: .module,
            comment: "Title for cancel button on the object capture screen.")

        static let numOfImages = String(
            localized: "%d/%d (Format, # of Images)",
            defaultValue: "%d/%d",
            bundle: .module,
            comment: "Images taken over maximum number of images.")

        static let help = String(
            localized: "Help (Object Capture)",
            defaultValue: "Help",
            bundle: .module,
            comment: "Title for help button on the object capture screen to show the tutorial pages.")
    }
}

#endif
