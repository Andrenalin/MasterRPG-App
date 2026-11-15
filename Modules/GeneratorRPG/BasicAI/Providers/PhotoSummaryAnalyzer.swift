// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import CoreRPG
import Foundation
import FoundationModels
import ImageIO

/// The model that produced an analysis.
public enum PhotoAnalysisModel: String, Sendable, Equatable, CaseIterable {
    case onDevice
    case privateCloud
}

/// Analyzes one photo with Foundation Models image input.
///
/// The on-device model runs first. When it is unavailable, cannot take images or fails in a way
/// the cloud can fix (see `PhotoAnalysisFallbackPolicy`), the analysis moves to Private Cloud
/// Compute, but only when `cloudConsent` allows a photo to leave the device.
@available(anyAppleOS 27.0, *)
@available(tvOS, unavailable)
public struct PhotoSummaryAnalyzer: Sendable {

    public struct Output: Sendable, Equatable {
        public let analysis: PhotoSummaryAnalysis
        public let model: PhotoAnalysisModel
    }

    /// Whether this process may use Private Cloud Compute.
    ///
    /// Creating a `PrivateCloudComputeLanguageModel` in a process without the managed entitlement
    /// `com.apple.developer.private-cloud-compute` is a fatal error, not a thrown one. The
    /// entitlement needs Apple's approval, so the cloud path stays off until the app has it, the
    /// GeneratorRPG target defines the `PRIVATE_CLOUD_COMPUTE_ENTITLED` compilation condition and
    /// the host has the entitlement (read from the code signature on macOS, declared by the host
    /// elsewhere). See `PrivateCloudComputeGate`.
    public static var isPrivateCloudComputeEnabled: Bool {
#if PRIVATE_CLOUD_COMPUTE_ENTITLED
        let compileTimeFlag = true
#else
        let compileTimeFlag = false
#endif
        return PrivateCloudComputeGate.isEnabled(
            compileTimeFlag: compileTimeFlag,
            processEntitlement: PrivateCloudComputeGate.processEntitlement(),
            hostDeclaration: PrivateCloudComputeGate.isHostDeclaredEntitled
        )
    }

    /// Called once at launch by a host app that carries the Private Cloud Compute entitlement.
    /// Hosts without it, such as an extension that links the module, do not call it.
    public static func declareHostPrivateCloudComputeEntitlement(_ entitled: Bool) {
        PrivateCloudComputeGate.declareHost(entitled: entitled)
    }

    private let instructions: String

    public init() {
        instructions = Self.defaultInstructions
    }

    init(instructions: String) {
        self.instructions = instructions
    }

    public func analyze(
        image: CGImage,
        outputLanguage: String = "English",
        cloudConsent: PhotoCloudConsent
    ) async throws -> Output {
        let onDeviceModel = SystemLanguageModel.default
        var fallbackReason = PhotoAnalysisFallbackPolicy.reasonToSkipOnDevice(
            availability: onDeviceModel.availability,
            capabilities: onDeviceModel.capabilities
        )
        var onDeviceError: (any Error)?

        if fallbackReason == nil {
            do {
                let analysis = try await analyze(image: image, outputLanguage: outputLanguage, using: .onDevice)
                return Output(analysis: analysis, model: .onDevice)
            } catch {
                guard let reason = PhotoAnalysisFallbackPolicy.reason(forOnDeviceError: error) else {
                    throw Self.mapped(error)
                }
                fallbackReason = reason
                onDeviceError = error
            }
        }

        if let failure = Self.cloudFallbackFailure(
            reason: fallbackReason,
            onDeviceError: onDeviceError,
            cloudEnabled: Self.isPrivateCloudComputeEnabled,
            consent: cloudConsent
        ) {
            throw failure
        }

        let analysis = try await analyze(image: image, outputLanguage: outputLanguage, using: .privateCloud)
        return Output(analysis: analysis, model: .privateCloud)
    }

    /// Runs one specific model without any fallback. The evaluation uses this to score each model
    /// on its own.
    public func analyze(
        image: CGImage,
        outputLanguage: String = "English",
        using model: PhotoAnalysisModel
    ) async throws -> PhotoSummaryAnalysis {
        let activeInstructions = instructions
            + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language."
        do {
            switch model {
            case .onDevice:
                guard SystemLanguageModel.default.availability == .available else {
                    throw PhotoSummaryAnalysisError.modelUnavailable
                }
                return try await respond(
                    session: LanguageModelSession(model: SystemLanguageModel.default, instructions: activeInstructions),
                    image: image,
                    outputLanguage: outputLanguage
                )
            case .privateCloud:
                guard Self.isPrivateCloudComputeEnabled else {
                    throw PhotoSummaryAnalysisError.modelUnavailable
                }
                let cloudModel = PrivateCloudComputeLanguageModel()
                guard cloudModel.availability == .available else {
                    throw PhotoSummaryAnalysisError.modelUnavailable
                }
                return try await respond(
                    session: LanguageModelSession(model: cloudModel, instructions: activeInstructions),
                    image: image,
                    outputLanguage: outputLanguage
                )
            }
        } catch let error as PhotoSummaryAnalysisError {
            throw error
        } catch {
            if model == .privateCloud, !(error is CancellationError) {
                throw PhotoSummaryAnalysisError.cloudFailed(error.localizedDescription)
            }
            throw error
        }
    }

    // MARK: - Private

    private func respond(
        session: LanguageModelSession,
        image: CGImage,
        outputLanguage: String
    ) async throws -> PhotoSummaryAnalysis {
        let response = try await session.respond(generating: PhotoSummaryAnalysis.self) {
            Self.prompt(outputLanguage: outputLanguage)
            Attachment(image)
        }
        return response.content
    }

    static func prompt(outputLanguage: String) -> String {
        """
        Analyze this image from a role-playing game.
        Output language: \(outputLanguage)

        Provide in \(outputLanguage):
        - A short title for the main subject
        - A description of what is visible, in 2 to 3 sentences
        - 3 to 5 specific tags in \(outputLanguage): what kind of image it is, what the main subject is, and the specific creatures, places, objects or mood you can see
        """
    }

    /// The error that ends the analysis before the cloud is tried, or `nil` when the cloud may run.
    ///
    /// Without the cloud (not entitled in this build) a failure the on-device model itself caused,
    /// for example a guardrail or an oversized context, keeps its own explanation. Only an
    /// unavailable or image-blind model reads as "Apple Intelligence is not available".
    static func cloudFallbackFailure(
        reason: PhotoAnalysisFallbackReason?,
        onDeviceError: (any Error)?,
        cloudEnabled: Bool,
        consent: PhotoCloudConsent
    ) -> (any Error)? {
        guard let reason else {
            return PhotoSummaryAnalysisError.modelUnavailable
        }
        guard cloudEnabled else {
            switch reason {
            case .onDeviceUnavailable, .visionUnsupported:
                return PhotoSummaryAnalysisError.modelUnavailable
            case .contextTooLarge, .guardrail, .unsupportedLanguage, .onDeviceLimited:
                return onDeviceError.map(mapped) ?? PhotoSummaryAnalysisError.cloudDeclined(reason)
            }
        }
        switch consent {
        case .allowed: return nil
        case .undecided: return PhotoSummaryAnalysisError.cloudConsentRequired(reason)
        case .denied: return PhotoSummaryAnalysisError.cloudDeclined(reason)
        }
    }

    private static func mapped(_ error: any Error) -> any Error {
        if error is CancellationError || error is PhotoSummaryAnalysisError {
            return error
        }
        return PhotoSummaryAnalysisError.generationFailed(error.localizedDescription)
    }

    private static let defaultInstructions = """
    You describe images for a role-playing game library: art, portraits, creatures, items, maps, \
    handouts and scenes.
    Provide a short title, a concise description and tags. Describe only what is visible and do \
    not invent names.
    Tags are short keywords (1 to 3 words) that tell this image apart from other RPG images: what \
    kind of image it is, its main subject, and specific things you can see such as creatures, \
    places, objects or mood. Write every tag in the output language, translate the kind of image \
    too. Never use generic tags that fit every RPG image, such as "RPG", "Setting", "System", \
    "Genre", "Image", "Art", "Artwork" or "Illustration" (or their translations), and never write a label before a value ("Genre: Fantasy"); \
    write only the value ("Fantasy").
    """
}

// MARK: - Image decoding

/// Decodes photo bytes into a bounded `CGImage` for the analysis.
public enum PhotoAnalysisImage {
    /// Downsampled image with its longest side at most `maximumPixelSize`, upright according to
    /// its EXIF orientation. `nil` when the bytes are not an image.
    public static func decode(
        data: Data,
        maximumPixelSize: Int = PhotoSummaryAnalyzerConstants.maximumPixelSize
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return thumbnail(from: source, maximumPixelSize: maximumPixelSize)
    }

    public static func decode(
        url: URL,
        maximumPixelSize: Int = PhotoSummaryAnalyzerConstants.maximumPixelSize
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return thumbnail(from: source, maximumPixelSize: maximumPixelSize)
    }

    /// A copy of `image` with its longest side at most `maximumPixelSize`; the image itself when it
    /// is already small enough.
    public static func downsampled(
        _ image: CGImage,
        maximumPixelSize: Int = PhotoSummaryAnalyzerConstants.maximumPixelSize
    ) -> CGImage? {
        let longestSide = max(image.width, image.height)
        guard longestSide > maximumPixelSize else {
            return image
        }
        let scale = Double(maximumPixelSize) / Double(longestSide)
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Goes through the shared downsampler so an image whose header declares more than the pixel
    /// limits is rejected before anything is decoded. See CODE_AUDIT §6.2.
    private static func thumbnail(from source: CGImageSource, maximumPixelSize: Int) -> CGImage? {
        ImageDownsampler.downsampledImage(from: source, maxPixelSize: CGFloat(maximumPixelSize))
    }
}

/// Constants that do not need the OS 27 analyzer, so image decoding stays available everywhere.
public enum PhotoSummaryAnalyzerConstants {
    /// Longest side sent to a model. The on-device context window is small and the photo only
    /// needs to be recognizable, not sharp.
    public static let maximumPixelSize = 1280
}

#endif
