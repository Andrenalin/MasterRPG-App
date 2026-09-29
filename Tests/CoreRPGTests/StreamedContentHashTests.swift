// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_19 §7.1: files are hashed in chunks instead of being read into memory; the
/// result must equal the in-memory hash, which existing items already store.
@Suite("Streamed content hash")
struct StreamedContentHashTests {
    @Test("The streamed hash equals the in-memory hash", arguments: [0, 1, (1 << 20) - 1, 1 << 20, (3 << 20) + 17])
    func streamedHashMatches(byteCount: Int) async throws {
        let data = Data((0..<byteCount).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = URL.temporaryDirectory.appending(path: "StreamedContentHash-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try FileUrl.contentHash(ofFileAt: url) == FileUrl.contentHash(of: data))
        #expect(try await FileManager.default.contentHash(coordinatingAccessAt: url) == FileUrl.contentHash(of: data))
    }
}
