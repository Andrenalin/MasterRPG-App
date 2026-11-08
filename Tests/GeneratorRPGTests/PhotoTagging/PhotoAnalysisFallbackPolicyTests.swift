// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import Foundation
import FoundationModels
import RPGResourcesDebug
import Testing

@testable import GeneratorRPG

/// When a failed on-device photo analysis may move to Private Cloud Compute. The mapping is pure,
/// so it runs in every test run without Apple Intelligence.
@Suite("Photo analysis fallback policy")
struct PhotoAnalysisFallbackPolicyTests {
    private let visionCapabilities = LanguageModelCapabilities([.vision, .guidedGeneration])
    private let textOnlyCapabilities = LanguageModelCapabilities([.guidedGeneration])

    @Test("A ready on-device model that takes images is used")
    func onDeviceIsUsed() {
        let reason = PhotoAnalysisFallbackPolicy.reasonToSkipOnDevice(
            availability: .available,
            capabilities: visionCapabilities
        )

        #expect(reason == nil)
    }

    @Test("A model that cannot take images is skipped")
    func visionMissing() {
        let reason = PhotoAnalysisFallbackPolicy.reasonToSkipOnDevice(
            availability: .available,
            capabilities: textOnlyCapabilities
        )

        #expect(reason == .visionUnsupported)
    }

    @Test("An unavailable model is skipped, whatever it could do", arguments: [
        SystemLanguageModel.Availability.unavailable(.appleIntelligenceNotEnabled),
        .unavailable(.deviceNotEligible),
        .unavailable(.modelNotReady)
    ])
    func unavailable(availability: SystemLanguageModel.Availability) {
        let reason = PhotoAnalysisFallbackPolicy.reasonToSkipOnDevice(
            availability: availability,
            capabilities: visionCapabilities
        )

        #expect(reason == .onDeviceUnavailable)
    }

    @Test("Errors the cloud can fix map to a reason")
    func recoverableErrors() {
        let cases: [(any Error, PhotoAnalysisFallbackReason)] = [
            (LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "")), .contextTooLarge),
            (LanguageModelError.guardrailViolation(.init(debugDescription: "")), .guardrail),
            (LanguageModelError.refusal(.init(explanation: "", debugDescription: "")), .guardrail),
            (LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .japanese, debugDescription: "")), .unsupportedLanguage),
            (LanguageModelError.unsupportedCapability(.init(capability: .vision, debugDescription: "")), .visionUnsupported),
            (LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "")), .onDeviceLimited),
            (SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "")), .onDeviceUnavailable)
        ]

        for (error, expected) in cases {
            #expect(PhotoAnalysisFallbackPolicy.reason(forOnDeviceError: error) == expected, "\(error)")
        }
    }

    @Test("Errors the cloud cannot fix stay errors")
    func unrecoverableErrors() {
        let errors: [any Error] = [
            CancellationError(),
            LanguageModelError.timeout(.init(debugDescription: "")),
            LanguageModelError.unsupportedGenerationGuide(.init(schemaName: nil, debugDescription: "")),
            PhotoSummaryAnalysisError.imageUnavailable,
            URLError(.notConnectedToInternet)
        ]

        for error in errors {
            #expect(PhotoAnalysisFallbackPolicy.reason(forOnDeviceError: error) == nil, "\(error)")
        }
    }
}

@Suite("Photo cloud consent")
struct PhotoCloudConsentTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "PhotoCloudConsentTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Nothing stored means undecided, and undecided keeps photos on the device")
    func defaultIsUndecided() throws {
        let defaults = try makeDefaults()

        #expect(PhotoCloudConsent.stored(in: defaults) == .undecided)
        #expect(!PhotoCloudConsent.undecided.permitsCloud)
        #expect(!PhotoCloudConsent.denied.permitsCloud)
        #expect(PhotoCloudConsent.allowed.permitsCloud)
    }

    @Test("The decision is remembered and can be changed", arguments: [
        PhotoCloudConsent.allowed, .denied, .undecided
    ])
    func remembered(decision: PhotoCloudConsent) throws {
        let defaults = try makeDefaults()
        PhotoCloudConsent.allowed.store(in: defaults)

        decision.store(in: defaults)

        #expect(PhotoCloudConsent.stored(in: defaults) == decision)
    }

    @Test("An unknown stored value counts as undecided")
    func unknownValue() throws {
        let defaults = try makeDefaults()
        defaults.set("maybe", forKey: PhotoCloudConsent.defaultsKey)

        #expect(PhotoCloudConsent.stored(in: defaults) == .undecided)
    }
}

@Suite("Photo analysis image")
struct PhotoAnalysisImageTests {
    @Test("A large photo is downsampled to the model's size limit")
    @MainActor
    func downsampled() throws {
        let source = try #require(ResourcesDebug.testPhotoCGImage(named: ResourcesDebug.wizardPhoto))
        #expect(max(source.width, source.height) > 512)

        let image = try #require(PhotoAnalysisImage.downsampled(source, maximumPixelSize: 512))

        #expect(max(image.width, image.height) == 512)
        // The aspect ratio stays.
        let ratioBefore = Double(source.width) / Double(source.height)
        let ratioAfter = Double(image.width) / Double(image.height)
        #expect(abs(ratioBefore - ratioAfter) < 0.01)
    }

    @Test("A small photo is returned as it is")
    @MainActor
    func smallPhotoUnchanged() throws {
        let source = try #require(ResourcesDebug.testPhotoCGImage(named: ResourcesDebug.wizardPhoto))

        let image = try #require(PhotoAnalysisImage.downsampled(source, maximumPixelSize: 100_000))

        #expect(image.width == source.width)
        #expect(image.height == source.height)
    }

    @Test("Bytes that are not an image give no image")
    func notAnImage() {
        #expect(PhotoAnalysisImage.decode(data: Data("not an image".utf8)) == nil)
    }
}

#endif
