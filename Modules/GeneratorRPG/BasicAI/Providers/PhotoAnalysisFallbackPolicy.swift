// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

/// Why the on-device model could not analyze a photo.
public enum PhotoAnalysisFallbackReason: Sendable, Equatable {
    /// The on-device model is not ready: Apple Intelligence off, assets still downloading.
    case onDeviceUnavailable
    /// The on-device model cannot take images.
    case visionUnsupported
    /// The image and instructions do not fit the on-device context window.
    case contextTooLarge
    /// The on-device safety checks stopped the request or the model refused.
    case guardrail
    /// The output language is not supported on device.
    case unsupportedLanguage
    /// The on-device model is rate limited or lacks another needed capability.
    case onDeviceLimited
}

/// Decides when a failed on-device analysis may be retried with Private Cloud Compute. Pure
/// mapping, so it is tested without a model.
@available(anyAppleOS 27.0, *)
@available(tvOS, unavailable)
enum PhotoAnalysisFallbackPolicy {
    /// The reason to skip the on-device model before trying it, or `nil` when it can take photos.
    static func reasonToSkipOnDevice(
        availability: SystemLanguageModel.Availability,
        capabilities: LanguageModelCapabilities
    ) -> PhotoAnalysisFallbackReason? {
        guard case .available = availability else {
            return .onDeviceUnavailable
        }
        return capabilities.contains(.vision) ? nil : .visionUnsupported
    }

    /// The reason a thrown on-device error may be retried in the cloud, or `nil` for errors the
    /// cloud cannot fix (cancellation, a bad schema, a timeout the person can simply retry).
    static func reason(forOnDeviceError error: any Error) -> PhotoAnalysisFallbackReason? {
        if error is SystemLanguageModel.Error {
            return .onDeviceUnavailable
        }
        if error as? PhotoSummaryAnalysisError == .declinedByModel {
            return .guardrail
        }
        guard let error = error as? LanguageModelError else {
            return nil
        }
        switch error {
        case .contextSizeExceeded: return .contextTooLarge
        case .guardrailViolation, .refusal: return .guardrail
        case .unsupportedLanguageOrLocale: return .unsupportedLanguage
        case .unsupportedCapability: return .visionUnsupported
        case .rateLimited: return .onDeviceLimited
        default: return nil
        }
    }
}

#endif
