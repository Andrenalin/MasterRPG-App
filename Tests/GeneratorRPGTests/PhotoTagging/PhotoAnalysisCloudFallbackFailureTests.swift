// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// What the person is told when the on-device analysis cannot finish and the cloud is not an option.
@Suite("Photo analysis cloud fallback failure")
struct PhotoAnalysisCloudFallbackFailureTests {
    private struct DeviceFailure: LocalizedError {
        var errorDescription: String? { "too large" }
    }

    @Test("Without the cloud a failure of the model keeps its own explanation")
    func deviceFailureKeepsItsExplanationWithoutCloud() {
        let failure = PhotoSummaryAnalyzer.cloudFallbackFailure(
            reason: .contextTooLarge,
            onDeviceError: DeviceFailure(),
            cloudEnabled: false,
            consent: .allowed
        )

        #expect(failure as? PhotoSummaryAnalysisError == .generationFailed("too large"))
    }

    @Test("Without the cloud an unavailable model still reads as unavailable")
    func unavailableModelStaysUnavailable() {
        for reason in [PhotoAnalysisFallbackReason.onDeviceUnavailable, .visionUnsupported] {
            let failure = PhotoSummaryAnalyzer.cloudFallbackFailure(
                reason: reason,
                onDeviceError: nil,
                cloudEnabled: false,
                consent: .allowed
            )

            #expect(failure as? PhotoSummaryAnalysisError == .modelUnavailable)
        }
    }

    @Test("With the cloud the consent decides")
    func consentDecidesWithCloud() {
        let allowed = PhotoSummaryAnalyzer.cloudFallbackFailure(
            reason: .guardrail, onDeviceError: DeviceFailure(), cloudEnabled: true, consent: .allowed)
        let undecided = PhotoSummaryAnalyzer.cloudFallbackFailure(
            reason: .guardrail, onDeviceError: DeviceFailure(), cloudEnabled: true, consent: .undecided)
        let denied = PhotoSummaryAnalyzer.cloudFallbackFailure(
            reason: .guardrail, onDeviceError: DeviceFailure(), cloudEnabled: true, consent: .denied)

        #expect(allowed == nil)
        #expect(undecided as? PhotoSummaryAnalysisError == .cloudConsentRequired(.guardrail))
        #expect(denied as? PhotoSummaryAnalysisError == .cloudDeclined(.guardrail))
    }

    @Test("No fallback reason means no model could run")
    func noReasonIsUnavailable() {
        let failure = PhotoSummaryAnalyzer.cloudFallbackFailure(
            reason: nil, onDeviceError: nil, cloudEnabled: true, consent: .allowed)

        #expect(failure as? PhotoSummaryAnalysisError == .modelUnavailable)
    }
}

#endif
