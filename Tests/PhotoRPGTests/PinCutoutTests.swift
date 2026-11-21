// @copyright André Trettin

import CoreVideo
import Foundation
import Testing

@testable import PhotoRPG

@Suite("Pin cutout")
struct PinCutoutTests {
    @Test("Only a subject that is neither noise nor the whole frame is usable", arguments: [
        (0.0, false), (0.04, false), (0.05, true), (0.4, true), (0.95, true), (0.96, false), (1.0, false),
    ])
    func coverageGate(coverage: Double, expected: Bool) {
        #expect(PinCutoutPolicy.isUsable(coverage: coverage) == expected)
    }

    @Test("The cache key changes with the file, its content and the generator revision")
    func keyInvalidation() {
        let photoId = UUID()
        let fileId = UUID()
        let base = PinCutoutKey(photoId: photoId, fileId: fileId, contentHash: "abc")

        #expect(base == PinCutoutKey(photoId: photoId, fileId: fileId, contentHash: "abc"))
        #expect(base != PinCutoutKey(photoId: photoId, fileId: fileId, contentHash: "abd"))
        #expect(base != PinCutoutKey(photoId: photoId, fileId: UUID(), contentHash: "abc"))
        #expect(base != PinCutoutKey(photoId: photoId, fileId: fileId, contentHash: "abc", revision: PinCutoutPolicy.revision + 1))
        #expect(base.fileName != PinCutoutKey(photoId: photoId, fileId: fileId, contentHash: "abd").fileName)
        #expect(base.fileName.hasSuffix(".png"))
    }

    @Test("Coverage counts the non-background pixels of an instance-label buffer")
    func coverageOfLabelBuffer() throws {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 10, 10, kCVPixelFormatType_OneComponent8, nil, &buffer) == kCVReturnSuccess)
        let mask = try #require(buffer)
        CVPixelBufferLockBaseAddress(mask, [])
        let base = try #require(CVPixelBufferGetBaseAddress(mask)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        for row in 0..<10 {
            for column in 0..<10 {
                // A 5x4 block of instance 1 and background elsewhere: 20 of 100 pixels.
                base[row * bytesPerRow + column] = (row < 4 && column < 5) ? 1 : 0
            }
        }
        CVPixelBufferUnlockBaseAddress(mask, [])

        let coverage = try #require(PinCutoutGenerator.coverage(of: mask))
        #expect(abs(coverage - 0.2) < 1e-9)
    }

    @Test("A buffer in another pixel format skips the coverage gate")
    func unknownFormatSkipsGate() throws {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)

        #expect(PinCutoutGenerator.coverage(of: pixels) == nil)
    }
}
