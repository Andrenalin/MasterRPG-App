// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import RolePlayGameKit

@Suite("Foundry media normalization")
struct FoundryMediaNormalizerTests {
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
