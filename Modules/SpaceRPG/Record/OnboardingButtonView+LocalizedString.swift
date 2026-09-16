/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The localized strings the onboarding button view uses.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation

extension OnboardingButtonView {
    struct LocalizedString {
        static let `continue` = String(
            localized: "Continue (Object Capture, Point Cloud)",
            defaultValue: "Continue",
            bundle: .module,
            comment: "Title of button to continue to flip the object and capture more."
        )

        static let finish = String(
            localized: "Finish (Object Capture, Point Cloud)",
            defaultValue: "Finish",
            bundle: .module,
            comment: "Title for finish button on the object capture screen."
        )

        static let skip = String(
            localized: "Skip (Object Capture, Point Cloud)",
            defaultValue: "Skip",
            bundle: .module,
            comment: "Title for skip button on the object capture screen."
        )

        static let cannotFlipYourObject = String(
            localized: "Can't flip your object? (Object Capture, Point Cloud)",
            defaultValue: "Can't flip your object?",
            bundle: .module,
            comment: "Title for button on the object capture screen that lets users indicate that their object cannot be flipped."
        )

        static let flipAnyway = String(
            localized: "Flip object anyway (Object Capture, Point Cloud)",
            defaultValue: "Flip object anyway",
            bundle: .module,
            comment: "Title for button on the object capture screen that lets users indicate they want to flip their object."
        )

        static let cancel = String(
            localized: "Cancel (Object Capture, Point Cloud)",
            defaultValue: "Cancel",
            bundle: .module,
            comment: "Title of button to close review page."
        )
    }
}

#endif
