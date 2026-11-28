// @copyright André Trettin

#if !os(tvOS)
import Foundation

/// Why a photo could not be analyzed.
public enum PhotoSummaryAnalysisError: LocalizedError, Equatable {
    /// The photo could not be read or decoded.
    case imageUnavailable
    /// Neither the on-device model nor Private Cloud Compute can run the analysis.
    case modelUnavailable
    /// The on-device model cannot analyze this photo, and the person has not allowed the cloud yet.
    case cloudConsentRequired(PhotoAnalysisFallbackReason)
    /// The on-device model cannot analyze this photo, and the person has declined the cloud.
    case cloudDeclined(PhotoAnalysisFallbackReason)
    /// Private Cloud Compute failed, for example offline or over its daily limit.
    case cloudFailed(String)
    case generationFailed(String)
    /// The on-device model answered with a refusal instead of a description.
    case declinedByModel

    public var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            String(localized: "The photo could not be read.", bundle: .module)
        case .modelUnavailable:
            String(
                localized: "Apple Intelligence is not available. Photo analysis requires it.",
                bundle: .module
            )
        case .cloudConsentRequired:
            String(
                localized: "The on-device model cannot analyze this photo. Allow Private Cloud Compute to continue.",
                bundle: .module
            )
        case .cloudDeclined:
            String(
                localized: "The on-device model cannot analyze this photo, and Private Cloud Compute is turned off.",
                bundle: .module
            )
        case .cloudFailed(let details):
            String(localized: "Private Cloud Compute could not analyze the photo: \(details)", bundle: .module)
        case .generationFailed(let details):
            String(localized: "Failed to analyze the photo: \(details)", bundle: .module)
        case .declinedByModel:
            String(localized: "The on-device model declined to describe this photo.", bundle: .module)
        }
    }
}

#endif
