/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Device orbit component of a data model that maintains the state of the app.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation

extension AppDataModel {
    enum Orbit: Int, CaseIterable, Identifiable, Comparable {
        case orbit1, orbit2, orbit3

        var id: Int {
            rawValue
        }

        var image: String {
            let imagesByIndex = ["1.circle", "2.circle", "3.circle"]
            return imagesByIndex[id]
        }

        var imageSelected: String {
            let imagesByIndex = ["1.circle.fill", "2.circle.fill", "3.circle.fill"]
            return imagesByIndex[id]
        }

        func next() -> Self {
            guard let currentIndex = Self.allCases.firstIndex(of: self) else { return self }
            let nextIndex = Self.allCases.index(after: currentIndex)
            return Self.allCases[nextIndex == Self.allCases.endIndex ? Self.allCases.endIndex - 1 : nextIndex]
        }

        func feedbackString(isObjectFlippable: Bool) -> String {
            switch self {
                case .orbit1:
                    return String(
                        localized: "Move slowly around your object. (Object Capture, Segment, Feedback)",
                        defaultValue: "Move slowly around your object.",
                        bundle: .module,
                        comment: "Guided feedback message to move slowly around object to start capturing."
                    )
                case .orbit2, .orbit3:
                    if isObjectFlippable {
                        return String(
                            localized: "Flip object on its side and move around. (Object Capture, Segment, Feedback)",
                            defaultValue: "Flip object on its side and move around.",
                            bundle: .module,
                            comment: "Guided feedback message for user to move around object again after flipping."
                        )
                    } else {
                        if case .orbit2 = self {
                            return String(
                                localized: "Move low and capture again. (Object Capture, Segment, Feedback)",
                                defaultValue: "Move low and capture again.",
                                bundle: .module,
                                comment: "Guided feedback message for user to move around object again from a lower angle without flipping"
                            )
                        }
                        return String(
                            localized: "Move above your object and capture again. (Object Capture, Segment, Feedback)",
                            defaultValue: "Move above your object and capture again.",
                            bundle: .module,
                            comment: "Guided feedback message for user to move around object again from a higher angle without flipping"
                        )
                    }
            }
        }

        func feedbackVideoName(isRegularWidth: Bool, isObjectFlippable: Bool) -> String {
            switch self {
                case .orbit1:
                    return isRegularWidth ? "ScanPasses-iPad-FixedHeight-1" : "ScanPasses-iPhone-FixedHeight-1"
                case .orbit2:
                    let iPhoneVideoName = isObjectFlippable ? "ScanPasses-iPhone-FixedHeight-2" : "ScanPasses-iPhone-FixedHeight-unflippable-low"
                    let iPadVideoName = isObjectFlippable ? "ScanPasses-iPad-FixedHeight-2" : "ScanPasses-iPad-FixedHeight-unflippable-low"
                    return isRegularWidth ? iPadVideoName : iPhoneVideoName
                case .orbit3:
                    let iPhoneVideoName = isObjectFlippable ? "ScanPasses-iPhone-FixedHeight-3" : "ScanPasses-iPhone-FixedHeight-unflippable-high"
                    let iPadVideoName = isObjectFlippable ? "ScanPasses-iPad-FixedHeight-3" : "ScanPasses-iPad-FixedHeight-unflippable-high"
                    return isRegularWidth ? iPadVideoName : iPhoneVideoName
            }
        }

        static func < (lhs: AppDataModel.Orbit, rhs: AppDataModel.Orbit) -> Bool {
            guard let lhsIndex = Self.allCases.firstIndex(of: lhs),
                  let rhsIndex = Self.allCases.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
    }
}

extension AppDataModel {
    // A segment can have n orbits. An orbit can reset to go from the capturing state back to it's initial state.
    enum OrbitState {
        case initial, capturing
    }
}

#endif
