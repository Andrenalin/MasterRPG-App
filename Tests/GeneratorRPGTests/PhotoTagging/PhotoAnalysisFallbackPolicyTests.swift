// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import CoreRPG
import Foundation
import FoundationModels
import ImageIO
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

    @Test("A photo that is one pixel over the dimension limit is not decoded, one at the limit is")
    func declaredOverLimitIsRejected() throws {
        // Given: two real, tiny PNGs, 16,384 x 1 (the limit) and 16,385 x 1 (over it). See
        // CODE_AUDIT §6.2.
        let atLimit = Self.png(width: ImageDownsampler.maximumDeclaredDimension, height: 1)
        let overLimit = Self.png(width: ImageDownsampler.maximumDeclaredDimension + 1, height: 1)
        let overSource = try #require(CGImageSourceCreateWithData(overLimit as CFData, nil))
        #expect(ImageDownsampler.declaredSize(of: overSource) == .overLimits)

        // When / Then
        #expect(PhotoAnalysisImage.decode(data: atLimit) != nil)
        #expect(PhotoAnalysisImage.decode(data: overLimit) == nil)
    }

    /// A valid grayscale PNG of `width` x `height` black pixels. The pixel data is one stored
    /// (uncompressed) zlib block, so it stays under 64 KB.
    private static func png(width: Int, height: Int) -> Data {
        func bigEndian(_ value: UInt32) -> [UInt8] {
            [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
        func crc32(_ bytes: [UInt8]) -> UInt32 {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
                }
            }
            return ~crc
        }
        func adler32(_ bytes: [UInt8]) -> UInt32 {
            var low: UInt32 = 1
            var high: UInt32 = 0
            for byte in bytes {
                low = (low + UInt32(byte)) % 65_521
                high = (high + low) % 65_521
            }
            return (high << 16) | low
        }
        func chunk(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            let body = Array(type.utf8) + payload
            return bigEndian(UInt32(payload.count)) + body + bigEndian(crc32(body))
        }
        let raw = [UInt8](repeating: 0, count: (1 + width) * height)
        precondition(raw.count <= 65_535)
        let length = UInt16(raw.count)
        let zlib: [UInt8] = [0x78, 0x01, 0x01, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
            + raw + bigEndian(adler32(raw))
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let header = bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 0, 0, 0, 0]
        return Data(signature + chunk("IHDR", header) + chunk("IDAT", zlib) + chunk("IEND", []))
    }
}

#endif
