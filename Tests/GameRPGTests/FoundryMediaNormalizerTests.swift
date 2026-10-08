// @copyright André Trettin

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import RolePlayGameKit

@Suite("Foundry media normalization")
struct FoundryMediaNormalizerTests {
    // CODE_AUDIT_21 §5.28: decoded before the query and fragment were cut off, an encoded `#`
    // in a file name ended the name there.
    @Test("An encoded # or ? in a file name is part of the name")
    func encodedFragmentCharactersStayInTheName() {
        let token = FoundryMediaNormalizer.plan(for: "tokens/Token%20%231.webp")
        #expect(token?.kind == .image)
        #expect(token?.suggestedFilename == "Token #1.jpg")
        #expect(FoundryMediaNormalizer.plan(for: "tokens/Who%3F.png?v=2#top")?.suggestedFilename == "Who?.jpg")
        #expect(FoundryMediaNormalizer.plan(for: "maps/dungeon.webp?cache=1")?.suggestedFilename == "dungeon.jpg")
    }

    @Test("Raster plans always install JPEG and reject vector resources")
    func imagePlanning() throws {
        // Given / When
        let png = try #require(
            FoundryMediaNormalizer.plan(for: "icons/Hero%20&amp;%20Portrait\u{0007}.PNG?v=2")
        )
        let webP = try #require(FoundryMediaNormalizer.plan(for: "maps/dungeon.webp"))

        // Then
        #expect(png.kind == .image)
        #expect(png.suggestedFilename == "Hero & Portrait.jpg")
        #expect(png.contentTypeIdentifier == UTType.jpeg.identifier)
        #expect(webP.suggestedFilename == "dungeon.jpg")
        #expect(FoundryMediaNormalizer.plan(for: "icons/token.svg") == nil)
        #expect(FoundryMediaNormalizer.plan(for: "icons/vector.pdf") == nil)
    }

    @Test("Opus and playlist-scoped WebM or MP4 plan MPEG-4 audio output")
    func audioPlanning() throws {
        // Given / When
        let opus = try #require(FoundryMediaNormalizer.plan(for: "audio/voice.opus"))
        let webM = try #require(
            FoundryMediaNormalizer.plan(
                for: "audio/ambience.webm",
                expectedKind: .audio
            )
        )
        let mp4 = try #require(
            FoundryMediaNormalizer.plan(
                for: "audio/theme.mp4",
                expectedKind: .audio
            )
        )

        // Then
        #expect(opus.kind == .audio)
        #expect(opus.suggestedFilename == "voice.m4a")
        #expect(webM.suggestedFilename == "ambience.m4a")
        #expect(mp4.suggestedFilename == "theme.m4a")
        #expect(FoundryMediaNormalizer.plan(for: "video/cutscene.webm") == nil)
    }

    @Test("PNG bytes become opaque JPEG bytes")
    func convertsPNGToJPEG() async throws {
        // Given
        let plan = try #require(FoundryMediaNormalizer.plan(for: "icons/pixel.png"))
        let source = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+R0YdWQAAAABJRU5ErkJggg=="
        ))

        // When
        let converted = try await plan.normalize(source)

        // Then
        #expect(converted.starts(with: [0xff, 0xd8, 0xff]))
        #expect(converted.suffix(2).elementsEqual([0xff, 0xd9]))
        #expect(converted != source)
    }

    @Test("Invalid raster bytes fail instead of being installed under a JPEG name")
    func rejectsInvalidRasterData() async throws {
        // Given
        let plan = try #require(FoundryMediaNormalizer.plan(for: "icons/not-an-image.png"))

        // When / Then
        await #expect(throws: FoundryMediaNormalizationError.invalidImage) {
            try await plan.normalize(Data("not an image".utf8))
        }
    }

    @Test("A large image is stored downsampled to the size the app displays (CODE_AUDIT_Folder §6.4)")
    func downsamplesLargeImage() async throws {
        let plan = try #require(FoundryMediaNormalizer.plan(for: "maps/wide.png"))
        let source = try makePNG(width: 9_000, height: 16)

        let converted = try await plan.normalize(source)

        let image = try #require(decodedImage(converted))
        #expect(image.width == 8_192)
        #expect(image.height < 16)
    }

    @Test("An image declaring more pixels than the budget is refused before decoding (CODE_AUDIT_Folder §6.4)")
    func rejectsOversizedHeader() async throws {
        let plan = try #require(FoundryMediaNormalizer.plan(for: "maps/huge.png"))
        let source = try makePNG(width: 16_385, height: 1)

        await #expect(throws: FoundryMediaNormalizationError.invalidImage) {
            try await plan.normalize(source)
        }
    }

    @Test("Transparent areas become white, not black (CODE_AUDIT_Folder §6.4)")
    func flattensTransparencyOnWhite() async throws {
        let plan = try #require(FoundryMediaNormalizer.plan(for: "icons/clear.png"))
        let source = try makePNG(width: 8, height: 8, transparent: true)

        let converted = try await plan.normalize(source)

        let image = try #require(decodedImage(converted))
        let pixel = try #require(firstPixel(of: image))
        #expect(pixel.allSatisfy { $0 > 240 }, "expected white, got \(pixel)")
    }

    @Test("PCM WAV becomes an MPEG-4 audio container")
    func convertsWAVToMPEG4Audio() async throws {
        // Given
        let plan = try #require(FoundryMediaNormalizer.plan(for: "audio/intro.wav"))

        // When
        let converted = try await plan.normalize(makeSilentPCMWave())

        // Then
        #expect(plan.kind == .audio)
        #expect(plan.suggestedFilename == "intro.m4a")
        #expect(plan.contentTypeIdentifier == UTType.mpeg4Audio.identifier)
        #expect(String(data: converted.prefix(4), encoding: .ascii) != "RIFF")
        #expect(String(data: converted.dropFirst(4).prefix(4), encoding: .ascii) == "ftyp")
    }
}

private extension FoundryMediaNormalizerTests {
    struct ImageFixtureError: Error {}

    func makePNG(width: Int, height: Int, transparent: Bool = false) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageFixtureError() }
        if !transparent {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let image = context.makeImage() else { throw ImageFixtureError() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageFixtureError()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageFixtureError() }
        return output as Data
    }

    func decodedImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func firstPixel(of image: CGImage) -> [UInt8]? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? Array(pixel.prefix(3)) : nil
    }

    func makeSilentPCMWave(sampleRate: UInt32 = 8_000, sampleCount: UInt32 = 2_000) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataByteCount = sampleCount * UInt32(channelCount) * bytesPerSample
        var result = Data()
        result.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(UInt32(36) + dataByteCount, to: &result)
        result.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &result)
        appendLittleEndian(UInt16(1), to: &result)
        appendLittleEndian(channelCount, to: &result)
        appendLittleEndian(sampleRate, to: &result)
        appendLittleEndian(sampleRate * UInt32(channelCount) * bytesPerSample, to: &result)
        appendLittleEndian(channelCount * UInt16(bytesPerSample), to: &result)
        appendLittleEndian(bitsPerSample, to: &result)
        result.append(contentsOf: "data".utf8)
        appendLittleEndian(dataByteCount, to: &result)
        result.append(Data(repeating: 0, count: Int(dataByteCount)))
        return result
    }

    func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
