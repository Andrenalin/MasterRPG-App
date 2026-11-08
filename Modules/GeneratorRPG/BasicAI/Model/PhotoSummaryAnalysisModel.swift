// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import Foundation
import Observation

/// State of one photo analysis for the view: busy flag, error text and the pending question
/// whether a photo may go to Private Cloud Compute.
@available(anyAppleOS 27.0, *)
@MainActor @Observable
final class PhotoSummaryAnalysisModel {

    var isAnalyzing = false
    var lastError: String?
    /// Set when the on-device model cannot analyze the photo and the person has not decided about
    /// the cloud yet; the view asks and runs the analysis again.
    var pendingConsentReason: PhotoAnalysisFallbackReason?

    private let analyzer = PhotoSummaryAnalyzer()

    /// Analyzes `image`, or returns `nil` and sets `lastError` or `pendingConsentReason`.
    func analyze(
        image: CGImage,
        outputLanguage: String,
        consent: PhotoCloudConsent
    ) async -> PhotoSummaryAnalyzer.Output? {
        isAnalyzing = true
        lastError = nil
        pendingConsentReason = nil
        defer { isAnalyzing = false }

        do {
            return try await analyzer.analyze(image: image, outputLanguage: outputLanguage, cloudConsent: consent)
        } catch is CancellationError {
            return nil
        } catch PhotoSummaryAnalysisError.cloudConsentRequired(let reason) {
            pendingConsentReason = reason
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func clearError() {
        lastError = nil
    }
}

extension PhotoAnalysisFallbackReason {
    /// Why the on-device model is skipped, in words for the consent question.
    public var explanation: String {
        switch self {
        case .onDeviceUnavailable:
            String(localized: "Apple Intelligence on this device is not ready.", bundle: .module)
        case .visionUnsupported:
            String(localized: "The on-device model cannot read images.", bundle: .module)
        case .contextTooLarge:
            String(localized: "The photo is too large for the on-device model.", bundle: .module)
        case .guardrail:
            String(localized: "The on-device safety check stopped the analysis.", bundle: .module)
        case .unsupportedLanguage:
            String(localized: "The output language is not supported on this device.", bundle: .module)
        case .onDeviceLimited:
            String(localized: "The on-device model is busy or limited right now.", bundle: .module)
        }
    }
}

#endif
